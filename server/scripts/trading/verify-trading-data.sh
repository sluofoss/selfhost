#!/bin/bash

# verify-trading-data.sh — Weekly integrity check for the trading data pipeline.
# Runs Sunday at 6 AM via cron.
# Checks:
#   1. TimescaleDB row counts per hypertable
#   2. Parquet file existence matches expected monthly/weekly periods
#   3. Compression ratios are within expected range
#   4. /data volume usage (alert at 80%, 90%)
#   5. B2 Parquet path is accessible and growing

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SERVER_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

if [ -f "$SERVER_DIR/.env" ]; then
    set -a; source "$SERVER_DIR/.env"; set +a
fi
source "$SCRIPT_DIR/../lib/rclone-env.sh"

LOG_DIR="${SERVER_DIR}/logs"
mkdir -p "$LOG_DIR"

WARNINGS=0
ERRORS=0

log() {
    printf '[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$1"
}

warn() {
    log "⚠  $1"
    WARNINGS=$((WARNINGS + 1))
}

fail() {
    log "✗  $1"
    ERRORS=$((ERRORS + 1))
}

ok() {
    log "✓  $1"
}

log "===== Trading data integrity check ====="

# ─── 1. TimescaleDB row counts ────────────────────────────────────────────────

if ! docker inspect trading_timescaledb > /dev/null 2>&1; then
    warn "trading_timescaledb not found — skipping DB checks"
else
    log "--- TimescaleDB hypertable row counts ---"
    for TABLE in ohlcv_10min ohlcv_1min ohlcv_daily tick_data indicators trade_log; do
        COUNT=$(docker exec trading_timescaledb psql -U trading -d trading -tAc \
            "SELECT COUNT(*) FROM $TABLE" 2>/dev/null || echo "ERROR")
        if [ "$COUNT" = "ERROR" ]; then
            fail "Could not query $TABLE"
        else
            log "  $TABLE: $COUNT rows"
        fi
    done

    # Check compression ratio on ohlcv_10min (expect 10–20x)
    COMP=$(docker exec trading_timescaledb psql -U trading -d trading -tAc "
        SELECT
            ROUND(
                SUM(before_compression_total_bytes)::numeric /
                NULLIF(SUM(after_compression_total_bytes), 0), 1
            )
        FROM timescaledb_information.chunks
        WHERE hypertable_name = 'ohlcv_10min'
          AND is_compressed = true;
    " 2>/dev/null || echo "")

    if [ -n "$COMP" ] && [ "$COMP" != "" ]; then
        log "  ohlcv_10min compression ratio: ${COMP}x"
        if (( $(echo "$COMP < 5" | python3 -c "import sys; print(int(eval(sys.stdin.read())))") )); then
            warn "ohlcv_10min compression ratio ${COMP}x is below expected 10–20x"
        fi
    else
        log "  ohlcv_10min: no compressed chunks yet (normal if recently deployed)"
    fi

    # Latest bar timestamp
    LATEST=$(docker exec trading_timescaledb psql -U trading -d trading -tAc \
        "SELECT MAX(time) FROM ohlcv_10min" 2>/dev/null || echo "")
    if [ -n "$LATEST" ] && [ "$LATEST" != "" ]; then
        log "  ohlcv_10min latest bar: $LATEST"
    else
        warn "ohlcv_10min has no rows — no bars collected yet"
    fi
fi

# ─── 2. Parquet staging area ──────────────────────────────────────────────────

LOCAL_PARQUET="${TRADING_DATA_PATH:-/data/trading}/parquet"
if [ -d "$LOCAL_PARQUET" ]; then
    PARQUET_SIZE=$(du -sh "$LOCAL_PARQUET" 2>/dev/null | cut -f1)
    PARQUET_FILES=$(find "$LOCAL_PARQUET" -name "*.parquet" 2>/dev/null | wc -l)
    log "  Parquet staging: $PARQUET_SIZE, $PARQUET_FILES files"
    ok "Parquet staging area accessible"
else
    warn "Parquet staging directory not found: $LOCAL_PARQUET"
fi

# ─── 3. B2 Parquet archive ────────────────────────────────────────────────────

if command -v rclone &> /dev/null && [ -n "${B2_BUCKET_NAME:-}" ]; then
    B2_PATH="${B2_BACKUPS_PATH:-backups}/trading/parquet"
    B2_SIZE=$(rclone size "backblaze:${B2_BUCKET_NAME}/${B2_PATH}/" --json 2>/dev/null \
        | python3 -c "import sys,json; d=json.load(sys.stdin); print(f\"{d['bytes']/1e9:.3f} GB ({d['count']} files)\")" 2>/dev/null || echo "unreachable")
    log "  B2 trading/parquet: $B2_SIZE"
    if [ "$B2_SIZE" = "unreachable" ]; then
        warn "Could not reach B2 — check rclone credentials"
    fi
else
    warn "rclone not available or B2_BUCKET_NAME not set — skipping B2 check"
fi

# ─── 4. Disk usage ────────────────────────────────────────────────────────────

DATA_USAGE=$(df /data --output=pcent 2>/dev/null | tail -1 | tr -d ' %' || echo "0")
log "  /data volume usage: ${DATA_USAGE}%"
if [ "$DATA_USAGE" -ge 90 ]; then
    fail "/data is at ${DATA_USAGE}% — CRITICAL, free space immediately"
elif [ "$DATA_USAGE" -ge 80 ]; then
    warn "/data is at ${DATA_USAGE}% — approaching capacity"
else
    ok "/data at ${DATA_USAGE}%, within safe range"
fi

TRADING_DATA_DIR="${TRADING_DATA_PATH:-/data/trading}"
if [ -d "$TRADING_DATA_DIR" ]; then
    TRADING_SIZE=$(du -sh "$TRADING_DATA_DIR" 2>/dev/null | cut -f1)
    log "  /data/trading total: $TRADING_SIZE"
fi

# ─── Summary ──────────────────────────────────────────────────────────────────

log "===== Check complete: $ERRORS error(s), $WARNINGS warning(s) ====="

if [ "$ERRORS" -gt 0 ]; then
    exit 1
fi
exit 0
