#!/bin/bash

# export-parquet.sh — Trigger Parquet export in the data-collector container.
# Runs at 4 AM daily via cron (before sync-trading-b2.sh at 5 AM).
# Exports completed bar ranges to /data/trading/parquet/ using Hive partitioning.
#
# Partition layout:
#   ohlcv/market=US/interval=10min/YYYY-MM.parquet   (monthly)
#   ohlcv/market=US/interval=1min/YYYY-MM-Wnn.parquet (weekly)
#   ohlcv/market=US/interval=daily/YYYY.parquet       (yearly)
#   tick/market=US/YYYY-MM-DD.parquet                 (daily)

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SERVER_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

log() {
    printf '[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$1"
}

log "Starting Parquet export..."

# Check that the data-collector container is running
if ! docker inspect trading_data_collector > /dev/null 2>&1; then
    log "✗ trading_data_collector container not found — trading stack not deployed"
    exit 1
fi

if ! docker ps --filter "name=trading_data_collector" --filter "status=running" --format "{{.Names}}" | grep -q "trading_data_collector"; then
    log "✗ trading_data_collector is not running"
    exit 1
fi

# Invoke the parquet export module inside the running container.
# The module writes Parquet files to /data/parquet (bind-mounted from the host).
log "Running parquet_export inside trading_data_collector..."
docker exec trading_data_collector python -m parquet_export

log "✓ Parquet export completed"
