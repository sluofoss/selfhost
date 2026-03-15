#!/bin/bash

# Hourly Configuration Backup Script
# Syncs configuration files to B2 when they change
# Uses inotify for change detection

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
CONFIG_DIRS=(
    "$SERVER_DIR"
    "/data/immich"
)
B2_BUCKET="${B2_BUCKET_NAME:?B2_BUCKET_NAME not set - configure server/.env}"
B2_PATH="${B2_BACKUPS_PATH:-backups}/configs"
LAST_BACKUP_FILE="/tmp/last-config-backup"

# Logging function
log() {
    printf '[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$1"
}

# Function to backup configs
backup_configs() {
    log "Checking for configuration changes..."
    
    CHANGES_FOUND=false
    TEMP_DIR=$(mktemp -d)
    
    for dir in "${CONFIG_DIRS[@]}"; do
        if [ -d "$dir" ]; then
            # Create hash of directory
            CURRENT_HASH=$(find "$dir" -type f \( -name "*.yml" -o -name "*.yaml" -o -name "*.env" -o -name "*.sh" -o -name "*.json" \) -exec md5sum {} \; 2>/dev/null | sort | md5sum | cut -d' ' -f1)
            
            HASH_FILE="/tmp/config-hash-$(echo "$dir" | tr '/' '_')"
            
            if [ -f "$HASH_FILE" ]; then
                OLD_HASH=$(cat "$HASH_FILE")
                if [ "$CURRENT_HASH" != "$OLD_HASH" ]; then
                    log "Changes detected in $dir"
                    CHANGES_FOUND=true
                fi
            else
                log "Initial backup for $dir"
                CHANGES_FOUND=true
            fi
            
            echo "$CURRENT_HASH" > "$HASH_FILE"
            
            # Copy relevant files to temp dir
            find "$dir" -type f \( -name "*.yml" -o -name "*.yaml" -o -name "*.env" -o -name "*.sh" -o -name "*.json" \) -exec cp --parents {} "$TEMP_DIR" \; 2>/dev/null || true
        fi
    done
    
    if [ "$CHANGES_FOUND" = true ]; then
        log "Syncing configurations to B2..."
        
        # Create timestamped backup
        BACKUP_NAME="config-$(date +%Y%m%d_%H%M%S).tar.gz"
        BACKUP_ARCHIVE="$(mktemp --tmpdir "${BACKUP_NAME%.tar.gz}.XXXXXX.tar.gz")"
        tar -czf "$BACKUP_ARCHIVE" -C "$TEMP_DIR" . 2>/dev/null
        
        # Sync to B2
        if command -v rclone &> /dev/null; then
            rclone copyto "$BACKUP_ARCHIVE" "backblaze:${B2_BUCKET}/${B2_PATH}/${BACKUP_NAME}"
            rclone sync "$TEMP_DIR" "backblaze:${B2_BUCKET}/${B2_PATH}/latest/"
            log "✓ Configurations synced to B2"
            
            # Cleanup old config backups (keep last 24)
            rclone delete --min-age 1d "backblaze:${B2_BUCKET}/${B2_PATH}/" --include "config-*.tar.gz"
        else
            log "✗ rclone not found, skipping B2 sync"
        fi
        
        rm -f "$BACKUP_ARCHIVE"
    else
        log "No configuration changes detected"
    fi
    
    rm -rf "$TEMP_DIR"
}

# Main execution
case "${1:-}" in
    --daemon)
        log "Starting configuration backup daemon..."
        while true; do
            backup_configs
            sleep 3600  # Run every hour
        done
        ;;
    *)
        backup_configs
        ;;
esac
