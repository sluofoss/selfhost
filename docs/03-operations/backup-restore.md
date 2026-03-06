# Backup & Restore

## Backup Strategy Overview

| Data Type | Frequency | Destination | Retention |
|-----------|-----------|-------------|-----------|
| PostgreSQL databases | Daily at 2 AM | Local + B2 | 7 days local, 30 days B2 |
| Configuration files | Hourly (on change) | B2 only | 24 hours |
| Full volume snapshots | Weekly (Sunday 3 AM) | B2 only | 4 weeks |

## Automated Backups

Backups run automatically via cron. No manual intervention needed.

### What's Backed Up

**Critical (Daily)**:
- Immich PostgreSQL database
- User metadata, albums, tags

**High Priority (Hourly)**:
- Docker Compose files
- Environment files (.env)
- Configuration changes

**Weekly**:
- Full thumbnails volume
- Complete system state

## Manual Backup Operations

### Database Backup

```bash
# Backup all databases
cd server
./scripts/backup/backup-postgres.sh

# Output: /data/backups/postgres/immich_YYYYMMDD_HHMMSS.sql.gz
```

### Configuration Backup

```bash
# Backup configs (runs hourly automatically)
./scripts/backup/backup-configs.sh
```

### Weekly Full Backup

```bash
# Full volume backup
./scripts/backup/backup-weekly.sh
```

## Restore Procedures

### Restore Database

```bash
# List available backups
ls -la /data/backups/postgres/

# Restore specific database
./scripts/backup/restore-postgres.sh immich /data/backups/postgres/immich_20240307_020000.sql.gz

# Or restore latest
./scripts/backup/restore-postgres.sh immich
```

**Warning**: This will overwrite the current database. Data since the backup will be lost.

### Restore Configuration

```bash
# Download from B2
rclone copy backblaze:backups/configs/latest/ ./restore/

# Copy files back
cp ./restore/* ./
```

### Full System Restore

**Scenario**: Complete server failure

```bash
# 1. Provision new server (use infra/)
# 2. Run setup
./scripts/setup/install.sh

# 3. Restore databases
rclone copy backblaze:backups/postgres/latest/ /data/backups/postgres/
./scripts/backup/restore-postgres.sh immich

# 4. Restore configs
rclone copy backblaze:backups/configs/latest/ ./

# 5. Start services
./start.sh
```

## Monitoring Backups

### Check Backup Status

```bash
# View recent backup logs
tail -20 /var/log/postgres-backup.log
tail -20 /var/log/config-backup.log

# List B2 backups
rclone ls backblaze:backups/
```

### Verify Backups

```bash
# Test database backup integrity
gunzip -t /data/backups/postgres/immich_*.sql.gz

# Check backup age
find /data/backups/postgres -mtime -1  # Files modified in last 24h
```

## Backup Storage

### Local Storage

Location: `/data/backups/`
- Fast restore
- 7-day retention
- Limited by block volume size (200GB)

### Backblaze B2

Location: `backups/` bucket
- Offsite durability
- 30+ day retention
- Primary restore source for disasters

### Cleanup

Old backups are automatically cleaned up:
- Local: Deleted after 7 days
- B2: Deleted after 30 days (configurable)

