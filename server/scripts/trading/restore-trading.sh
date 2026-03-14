#!/bin/bash

# restore-trading.sh — Restore trading TimescaleDB from a B2 pg_dump backup.
# Use after total instance loss; new TSDB must be running and empty before running this.
#
# Usage:
#   restore-trading.sh                   # restore latest backup
#   restore-trading.sh 20260314_020001   # restore specific date-stamped backup
#
# After restore, the data-collector will automatically backfill any bars missed
# between the backup timestamp and "now" via ib_insync reqHistoricalData.

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SERVER_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

if [ -f "$SERVER_DIR/.env" ]; then
    set -a; source "$SERVER_DIR/.env"; set +a
fi
source "$SCRIPT_DIR/../lib/rclone-env.sh"

log() {
    printf '[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$1"
}

B2_BUCKET="${B2_BUCKET_NAME:?B2_BUCKET_NAME not set — configure server/.env}"
B2_PG_PATH="${B2_BACKUPS_PATH:-backups}/postgres"
LOCAL_RESTORE_DIR="/tmp/trading-restore-$$"
REQUESTED_STAMP="${1:-}"

# ─── Locate the backup to restore ────────────────────────────────────────────

log "Listing available trading backups on B2..."
AVAILABLE=$(rclone lsf "backblaze:${B2_BUCKET}/${B2_PG_PATH}/" 2>/dev/null \
    | grep "^trading_" | sort -r || true)

if [ -z "$AVAILABLE" ]; then
    log "✗ No trading backups found at backblaze:${B2_BUCKET}/${B2_PG_PATH}/"
    exit 1
fi

if [ -n "$REQUESTED_STAMP" ]; then
    BACKUP_FILE="trading_${REQUESTED_STAMP}.sql.gz"
    if ! echo "$AVAILABLE" | grep -q "^${BACKUP_FILE}$"; then
        log "✗ Requested backup not found: $BACKUP_FILE"
        log "Available backups:"
        echo "$AVAILABLE" | head -10
        exit 1
    fi
else
    BACKUP_FILE=$(echo "$AVAILABLE" | head -1)
    log "Using latest backup: $BACKUP_FILE"
fi

# ─── Confirm before restoring ────────────────────────────────────────────────

log ""
log "  Backup to restore : $BACKUP_FILE"
log "  Target container  : trading_timescaledb"
log "  Target DB         : trading"
log ""
read -rp "This will DROP and recreate the trading database. Continue? (yes/N): " CONFIRM
if [ "$CONFIRM" != "yes" ]; then
    log "Aborted."
    exit 0
fi

# ─── Check target container is running ───────────────────────────────────────

if ! docker exec trading_timescaledb pg_isready -U trading > /dev/null 2>&1; then
    log "✗ trading_timescaledb is not running. Start it first:"
    log "   cd server/trading && docker compose up -d timescaledb"
    exit 1
fi

# ─── Download from B2 ────────────────────────────────────────────────────────

mkdir -p "$LOCAL_RESTORE_DIR"
trap 'rm -rf "$LOCAL_RESTORE_DIR"' EXIT

log "Downloading $BACKUP_FILE from B2..."
rclone copy "backblaze:${B2_BUCKET}/${B2_PG_PATH}/${BACKUP_FILE}" "$LOCAL_RESTORE_DIR/"
log "✓ Download complete"

# ─── Drop and recreate database ──────────────────────────────────────────────

log "Dropping existing trading database..."
docker exec trading_timescaledb psql -U trading -d postgres -c \
    "SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE datname = 'trading' AND pid <> pg_backend_pid();" \
    > /dev/null 2>&1 || true
docker exec trading_timescaledb psql -U trading -d postgres -c "DROP DATABASE IF EXISTS trading;"
docker exec trading_timescaledb psql -U trading -d postgres -c "CREATE DATABASE trading;"
log "✓ Database recreated"

# ─── Restore ─────────────────────────────────────────────────────────────────

log "Restoring from $BACKUP_FILE..."
zcat "${LOCAL_RESTORE_DIR}/${BACKUP_FILE}" | \
    docker exec -i trading_timescaledb psql -U trading -d trading
log "✓ Restore complete"

# ─── Post-restore verification ────────────────────────────────────────────────

log "Verifying restored schema..."
for TABLE in ohlcv_10min ohlcv_1min ohlcv_daily tick_data indicators; do
    COUNT=$(docker exec trading_timescaledb psql -U trading -d trading -tAc \
        "SELECT COUNT(*) FROM $TABLE" 2>/dev/null || echo "ERROR")
    if [ "$COUNT" = "ERROR" ]; then
        log "  ⚠  Could not query $TABLE"
    else
        log "  $TABLE: $COUNT rows"
    fi
done

log ""
log "===== Restore complete ====="
log "Next steps:"
log "  1. Start the full trading stack: docker compose up -d"
log "  2. Open https://tws.<domain> and log in to TWS via KasmVNC"
log "  3. The data-collector will auto-backfill missing bars on first market open"
