#!/bin/bash

# Daily PostgreSQL Backup Script
# Runs at 2 AM daily via cron
# Backups are stored locally and synced to B2

set -e

# Load environment variables
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SERVER_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
if [ -f "$SERVER_DIR/.env" ]; then
    set -a; source "$SERVER_DIR/.env"; set +a
fi
source "$SCRIPT_DIR/../lib/rclone-env.sh"
source "$SCRIPT_DIR/../lib/notify-telegram.sh"

# Configuration
BACKUP_DIR="/data/backups/postgres"
B2_BUCKET="${B2_BUCKET_NAME:?B2_BUCKET_NAME not set - configure server/.env}"
B2_PATH="${B2_BACKUPS_PATH:-backups}/postgres"
RETENTION_DAYS=7
DATE=$(date +%Y%m%d_%H%M%S)

# Ensure backup directory exists
mkdir -p "$BACKUP_DIR"

# Logging function
log() {
    printf '[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$1"
}

log "Starting PostgreSQL backup..."

# ─── Immich PostgreSQL ────────────────────────────────────────────────────────

if ! docker exec immich_postgres pg_isready -U postgres > /dev/null 2>&1; then
    log "⚠ immich_postgres not running, skipping Immich backup"
else
    DATABASES=(immich)
    for db in "${DATABASES[@]}"; do
        if ! docker exec immich_postgres psql -U postgres -lqt | cut -d \| -f 1 | grep -qw "$db"; then
            log "⚠ Database '$db' does not exist on immich_postgres, skipping"
            continue
        fi

        BACKUP_FILE="${BACKUP_DIR}/${db}_${DATE}.sql.gz"
        log "Backing up database: $db (immich_postgres)"
        docker exec immich_postgres pg_dump -U postgres "$db" | gzip > "$BACKUP_FILE"

        if [ -f "$BACKUP_FILE" ] && [ -s "$BACKUP_FILE" ]; then
            SIZE=$(du -h "$BACKUP_FILE" | cut -f1)
            log "✓ Backup created: $BACKUP_FILE ($SIZE)"
            if command -v rclone &> /dev/null; then
                rclone copy "$BACKUP_FILE" "backblaze:${B2_BUCKET}/${B2_PATH}/"
                log "✓ Synced $db to B2"
            fi
        else
            log "✗ Backup failed for database: $db"
        fi
    done
fi

# ─── Trading TimescaleDB ──────────────────────────────────────────────────────

if docker inspect trading_timescaledb > /dev/null 2>&1; then
    if ! docker exec trading_timescaledb pg_isready -U trading > /dev/null 2>&1; then
        log "⚠ trading_timescaledb not ready, skipping trading backup"
    else
        TRADING_BACKUP_FILE="${BACKUP_DIR}/trading_${DATE}.sql.gz"
        log "Backing up database: trading (trading_timescaledb)"
        docker exec trading_timescaledb pg_dump -U trading trading | gzip > "$TRADING_BACKUP_FILE"

        if [ -f "$TRADING_BACKUP_FILE" ] && [ -s "$TRADING_BACKUP_FILE" ]; then
            SIZE=$(du -h "$TRADING_BACKUP_FILE" | cut -f1)
            log "✓ Backup created: $TRADING_BACKUP_FILE ($SIZE)"
            if command -v rclone &> /dev/null; then
                rclone copy "$TRADING_BACKUP_FILE" "backblaze:${B2_BUCKET}/${B2_PATH}/"
                log "✓ Synced trading to B2"
            fi
        else
            log "✗ Backup failed for database: trading"
        fi
    fi
else
    log "trading_timescaledb not found, skipping trading backup (stack not deployed)"
fi

# Cleanup old backups (local)
log "Cleaning up old local backups (older than $RETENTION_DAYS days)..."
find "$BACKUP_DIR" -name "*.sql.gz" -mtime +$RETENTION_DAYS -delete

# Cleanup old backups (B2) - keep 30 days
if command -v rclone &> /dev/null; then
    log "Cleaning up old B2 backups..."
    rclone delete --min-age 30d "backblaze:${B2_BUCKET}/${B2_PATH}/"
fi

log "Backup completed"
