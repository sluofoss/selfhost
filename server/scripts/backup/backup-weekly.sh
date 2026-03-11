#!/bin/bash

# Weekly Bounded Backup Script
# Creates snapshots of critical local data volumes
# Syncs to B2 for disaster recovery

set -e

# Load environment variables
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SERVER_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
if [ -f "$SERVER_DIR/.env" ]; then
    set -a; source "$SERVER_DIR/.env"; set +a
fi
source "$SCRIPT_DIR/../lib/rclone-env.sh"

# Configuration
BACKUP_ROOT="/data/backups/weekly"
B2_BUCKET="${B2_BUCKET_NAME:?B2_BUCKET_NAME not set - configure server/.env}"
RETENTION_WEEKS=4
DATE=$(date +%Y%m%d)

# Directories to backup
# Rebuildable thumbnail/preview derivatives are intentionally excluded to keep
# the weekly snapshot bounded and aligned with the lean rebuild-first design.
BACKUP_DIRS=(
    "/data/backups/postgres"
    "/var/lib/docker/volumes"
)

# Logging function
log() {
    printf '[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$1"
}

log "Starting weekly bounded backup..."

# Create weekly backup directory
WEEKLY_DIR="${BACKUP_ROOT}/${DATE}"
mkdir -p "$WEEKLY_DIR"

# Create compressed archives
for dir in "${BACKUP_DIRS[@]}"; do
    if [ -d "$dir" ]; then
        BASENAME=$(basename "$dir")
        ARCHIVE="${WEEKLY_DIR}/${BASENAME}.tar.gz"
        
        log "Creating archive: $BASENAME"
        tar -czf "$ARCHIVE" -C "$(dirname "$dir")" "$(basename "$dir")" 2>/dev/null || {
            log "✗ Failed to create archive: $BASENAME"
            continue
        }
        
        SIZE=$(du -h "$ARCHIVE" | cut -f1)
        log "✓ Archive created: $ARCHIVE ($SIZE)"
    fi
done

# Sync to B2
if command -v rclone &> /dev/null; then
    log "Syncing weekly backup to B2..."
    rclone sync "$WEEKLY_DIR" "backblaze:${B2_BUCKET}/${B2_BACKUPS_PATH:-backups}/weekly/${DATE}/"
    log "✓ Weekly backup synced to B2"
    
    # Cleanup old weekly backups from B2. Deleting from the backup root with an
    # include filter avoids the slow direct `weekly/` prefix walk against B2.
    log "Cleaning up old weekly backups..."
    rclone delete --min-age ${RETENTION_WEEKS}w "backblaze:${B2_BUCKET}/${B2_BACKUPS_PATH:-backups}" --include "/weekly/**"
fi

# Cleanup local backups
log "Cleaning up old local weekly backups..."
find "$BACKUP_ROOT" -mindepth 1 -maxdepth 1 -type d -mtime +$((RETENTION_WEEKS * 7)) -exec rm -rf {} \;

log "Weekly backup completed"
