#!/bin/bash

# Daily PostgreSQL Backup Script
# Runs at 2 AM daily via cron
# Backups are stored locally and synced to B2

set -e

# Configuration
BACKUP_DIR="/data/backups/postgres"
B2_BUCKET="${B2_BACKUP_BUCKET:-backups}"
B2_PATH="${B2_BACKUP_PATH:-postgres}"
RETENTION_DAYS=7
DATE=$(date +%Y%m%d_%H%M%S)
LOG_FILE="/var/log/postgres-backup.log"

# Ensure backup directory exists
mkdir -p "$BACKUP_DIR"

# Logging function
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

log "Starting PostgreSQL backup..."

# Create backup for each database
for db in immich nextcloud; do
    if docker exec postgres pg_isready -U postgres > /dev/null 2>&1; then
        BACKUP_FILE="${BACKUP_DIR}/${db}_${DATE}.sql.gz"
        
        log "Backing up database: $db"
        
        # Create backup
        docker exec postgres pg_dump -U postgres "$db" | gzip > "$BACKUP_FILE"
        
        # Verify backup
        if [ -f "$BACKUP_FILE" ] && [ -s "$BACKUP_FILE" ]; then
            SIZE=$(du -h "$BACKUP_FILE" | cut -f1)
            log "✓ Backup created: $BACKUP_FILE ($SIZE)"
            
            # Sync to B2
            if command -v rclone &> /dev/null; then
                log "Syncing to B2..."
                rclone copy "$BACKUP_FILE" "backblaze:${B2_BUCKET}/${B2_PATH}/"
                log "✓ Synced to B2"
            fi
        else
            log "✗ Backup failed for database: $db"
        fi
    else
        log "✗ PostgreSQL not running, skipping backup"
    fi
done

# Cleanup old backups (local)
log "Cleaning up old local backups (older than $RETENTION_DAYS days)..."
find "$BACKUP_DIR" -name "*.sql.gz" -mtime +$RETENTION_DAYS -delete

# Cleanup old backups (B2) - keep 30 days
if command -v rclone &> /dev/null; then
    log "Cleaning up old B2 backups..."
    rclone delete --min-age 30d "backblaze:${B2_BUCKET}/${B2_PATH}/"
fi

log "Backup completed"
