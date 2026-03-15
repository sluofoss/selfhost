#!/bin/bash

# Hourly Seafile MariaDB Backup Script
# Runs every hour via cron
# MariaDB is the entry-point to the S3 object graph — missing it means losing
# everything since the last backup.  Hourly cadence shrinks that window to 1 h.

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SERVER_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

if [ -f "$SERVER_DIR/.env" ]; then
    set -a; source "$SERVER_DIR/.env"; set +a
fi
if [ -f "$SERVER_DIR/seafile/.env" ]; then
    set -a; source "$SERVER_DIR/seafile/.env"; set +a
fi
source "$SCRIPT_DIR/../lib/rclone-env.sh"
source "$SCRIPT_DIR/../lib/notify-telegram.sh"

BACKUP_DIR="/data/backups/seafile-db"
B2_BUCKET="${B2_BUCKET_NAME:?B2_BUCKET_NAME not set - configure server/.env}"
B2_PATH="${B2_BACKUPS_PATH:-backups}/seafile-db"
RETENTION_DAYS=2   # keep 2 days locally (48 hourly backups)
DATE=$(date +%Y%m%d_%H%M%S)

mkdir -p "$BACKUP_DIR"

log() {
    printf '[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$1"
}

log "Starting Seafile MariaDB backup..."

if ! docker exec seafile_db mysqladmin ping -u root -p"${INIT_SEAFILE_MYSQL_ROOT_PASSWORD}" --silent 2>/dev/null; then
    log "✗ Seafile MariaDB not running or not healthy, skipping backup"
    exit 1
fi

BACKUP_FILE="${BACKUP_DIR}/seafile_mariadb_${DATE}.sql.gz"

log "Dumping all Seafile databases..."
docker exec seafile_db mysqldump \
    -u root -p"${INIT_SEAFILE_MYSQL_ROOT_PASSWORD}" \
    --all-databases \
    --single-transaction \
    --quick \
    --lock-tables=false \
    | gzip > "$BACKUP_FILE"

if [ -f "$BACKUP_FILE" ] && [ -s "$BACKUP_FILE" ]; then
    SIZE=$(du -h "$BACKUP_FILE" | cut -f1)
    log "✓ Backup created: $BACKUP_FILE ($SIZE)"

    if command -v rclone &> /dev/null; then
        log "Syncing to B2..."
        rclone copy "$BACKUP_FILE" "backblaze:${B2_BUCKET}/${B2_PATH}/"
        log "✓ Synced to B2: ${B2_BUCKET}/${B2_PATH}/$(basename "$BACKUP_FILE")"
    fi
else
    log "✗ Backup file missing or empty"
    exit 1
fi

# Keep 2 days of local backups (48 files at hourly cadence)
log "Cleaning up local backups older than ${RETENTION_DAYS} days..."
find "$BACKUP_DIR" -name "*.sql.gz" -mtime +"$RETENTION_DAYS" -delete

# Keep 7 days in B2
if command -v rclone &> /dev/null; then
    log "Cleaning up B2 backups older than 7 days..."
    rclone delete --min-age 7d "backblaze:${B2_BUCKET}/${B2_PATH}/"
fi

log "Seafile MariaDB backup completed"
