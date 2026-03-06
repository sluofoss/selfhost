#!/bin/bash

# Weekly Full Volume Backup Script
# Creates snapshots of critical data volumes
# Syncs to B2 for disaster recovery

set -e

# Configuration
BACKUP_ROOT="/data/backups/weekly"
B2_BUCKET="${B2_BUCKET_NAME:-sluo-personal-b2}"
RETENTION_WEEKS=4
DATE=$(date +%Y%m%d)
LOG_FILE="/var/log/weekly-backup.log"

# Directories to backup
BACKUP_DIRS=(
    "/data/immich/thumbnails"
    "/data/backups/postgres"
    "/var/lib/docker/volumes"
)

# Logging function
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

log "Starting weekly full backup..."

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
    rclone sync "$WEEKLY_DIR" "backblaze:${B2_BUCKET}/backups/weekly/${DATE}/"
    log "✓ Weekly backup synced to B2"
    
    # Cleanup old weekly backups from B2
    log "Cleaning up old weekly backups..."
    rclone delete --min-age ${RETENTION_WEEKS}w "backblaze:${B2_BUCKET}/backups/weekly/"
fi

# Cleanup local backups
log "Cleaning up old local weekly backups..."
find "$BACKUP_ROOT" -mindepth 1 -maxdepth 1 -type d -mtime +$((RETENTION_WEEKS * 7)) -exec rm -rf {} \;

log "Weekly backup completed"
