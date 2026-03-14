#!/bin/bash

# sync-trading-b2.sh — Sync Parquet staging area to Backblaze B2.
# Runs at 5 AM daily via cron (after export-parquet.sh at 4 AM).
# Uses rclone sync so deleted/replaced local files are mirrored to B2.
# Parquet files on B2 are NEVER deleted by this script (they accumulate forever).

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SERVER_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Load server env for B2 credentials and paths
if [ -f "$SERVER_DIR/.env" ]; then
    set -a; source "$SERVER_DIR/.env"; set +a
fi
source "$SCRIPT_DIR/../lib/rclone-env.sh"

log() {
    printf '[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$1"
}

B2_BUCKET="${B2_BUCKET_NAME:?B2_BUCKET_NAME not set — configure server/.env}"
B2_TRADING_PATH="${B2_BACKUPS_PATH:-backups}/trading/parquet"
LOCAL_PARQUET="${TRADING_DATA_PATH:-/data/trading}/parquet"

log "Starting Parquet → B2 sync..."

if [ ! -d "$LOCAL_PARQUET" ]; then
    log "✗ Local Parquet directory not found: $LOCAL_PARQUET"
    exit 1
fi

if ! command -v rclone &> /dev/null; then
    log "✗ rclone not found"
    exit 1
fi

# Copy new/changed files to B2 (no --delete — B2 is the permanent archive)
log "Copying $LOCAL_PARQUET → backblaze:${B2_BUCKET}/${B2_TRADING_PATH}/"
rclone copy \
    "$LOCAL_PARQUET/" \
    "backblaze:${B2_BUCKET}/${B2_TRADING_PATH}/" \
    --progress \
    --transfers 4 \
    --b2-chunk-size 64M

log "✓ Parquet sync to B2 completed"

# Log B2 usage for monitoring
REMOTE_SIZE=$(rclone size "backblaze:${B2_BUCKET}/${B2_TRADING_PATH}/" --json 2>/dev/null | python3 -c "import sys,json; d=json.load(sys.stdin); print(f\"{d['bytes']/1e9:.2f} GB\")" 2>/dev/null || echo "unknown")
log "  B2 trading/parquet total: $REMOTE_SIZE"
