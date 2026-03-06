#!/bin/bash

# Database Restore Script
# Restores PostgreSQL databases from backup files

set -e

# Configuration
BACKUP_DIR="/data/backups/postgres"
LOG_FILE="/var/log/postgres-restore.log"

# Logging function
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

# Show usage
usage() {
    echo "Usage: $0 <database_name> [backup_file]"
    echo ""
    echo "Arguments:"
    echo "  database_name    Name of the database to restore (immich, nextcloud)"
    echo "  backup_file      Specific backup file to restore (optional)"
    echo ""
    echo "Available backups:"
    ls -1 "$BACKUP_DIR"/*.sql.gz 2>/dev/null || echo "  No backups found"
    exit 1
}

# Check arguments
if [ $# -lt 1 ]; then
    usage
fi

DB_NAME=$1
BACKUP_FILE=$2

# If no backup file specified, use the latest
if [ -z "$BACKUP_FILE" ]; then
    BACKUP_FILE=$(ls -1t "$BACKUP_DIR"/${DB_NAME}_*.sql.gz 2>/dev/null | head -1)
    if [ -z "$BACKUP_FILE" ]; then
        log "✗ No backup found for database: $DB_NAME"
        exit 1
    fi
fi

# Check if backup file exists
if [ ! -f "$BACKUP_FILE" ]; then
    log "✗ Backup file not found: $BACKUP_FILE"
    exit 1
fi

log "=================================="
log "Database Restore"
log "=================================="
log "Database: $DB_NAME"
log "Backup file: $BACKUP_FILE"
log ""

# Confirm restore
read -p "WARNING: This will overwrite the existing database. Continue? (yes/no): " confirm
if [ "$confirm" != "yes" ]; then
    log "Restore cancelled"
    exit 0
fi

# Check if PostgreSQL is running
if ! docker exec postgres pg_isready -U postgres > /dev/null 2>&1; then
    log "✗ PostgreSQL is not running"
    exit 1
fi

log "Stopping dependent services..."
docker stop immich-server immich-microservices 2>/dev/null || true
docker stop nextcloud 2>/dev/null || true

log "Dropping existing database..."
docker exec postgres dropdb -U postgres --if-exists "$DB_NAME"

log "Creating new database..."
docker exec postgres createdb -U postgres "$DB_NAME"

log "Restoring from backup..."
gunzip < "$BACKUP_FILE" | docker exec -i postgres psql -U postgres "$DB_NAME"

log "Starting dependent services..."
docker start immich-server immich-microservices 2>/dev/null || true
docker start nextcloud 2>/dev/null || true

log "✓ Database restore completed successfully"
