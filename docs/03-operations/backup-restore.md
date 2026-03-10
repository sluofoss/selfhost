# Backup & Restore

## Backup Strategy Overview

| Data Type | Frequency | Destination | Retention |
|-----------|-----------|-------------|-----------|
| PostgreSQL databases | Daily at 2 AM | Local + B2 | 7 days local, 30 days B2 |
| Configuration files | Hourly (on change) | B2 only | 24 hours |
| Full volume snapshots | Weekly (Sunday 3 AM) | Local + B2 | 4 weeks |
| Terraform state | On every `apply.sh` run | B2 | 90 days |
| SSL certificates | On creation | B2 | Forever |

**Note**: Original photos are stored directly in B2 via the rclone FUSE mount, so they don't need separate backup — B2 *is* the primary storage.

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

**Note on .env backups**: The hourly config backup includes `.env` files (which contain secrets like B2 keys and database passwords). These are stored in your B2 bucket which has encryption enabled. This is an acceptable trade-off for personal use — it means you can fully restore your setup from B2 alone.

**Weekly**:
- Full thumbnails volume
- Database dump archive
- Docker volumes

## Manual Backup Operations

### Database Backup

```bash
# Backup all databases
cd ~/selfhost/server
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
./scripts/backup/restore-postgres.sh immich /data/backups/postgres/immich_20260307_020000.sql.gz

# Or restore latest
./scripts/backup/restore-postgres.sh immich
```

**Warning**: This will overwrite the current database. Data since the backup will be lost.

### Restore Configuration

```bash
# Download from B2
rclone copy backblaze:${B2_BUCKET_NAME}/${B2_BACKUPS_PATH:-backups}/configs/latest/ ./restore/

# Copy files back
cp ./restore/* ./
```

### Full System Restore

**Scenario**: Complete server failure

```bash
# 1. Provision new server (use infra/)
cd infra && ./apply.sh

# 2. Wait for cloud-init to finish, then SSH in
ssh -i ~/.ssh/id_ed25519 ubuntu@<your-server-ip>

# 3. Configure .env files
cd ~/selfhost/server
cp .env.example .env
# Edit .env with your B2 credentials, domain, etc.

# 4. Run post-config setup
./scripts/setup/install.sh

# 5. Restore databases from B2
rclone copy backblaze:${B2_BUCKET_NAME}/${B2_BACKUPS_PATH:-backups}/postgres/ /data/backups/postgres/
./scripts/backup/restore-postgres.sh immich

# 6. Restore SSL certificates (if using Cloudflare Origin Certs)
rclone copy backblaze:${B2_BUCKET_NAME}/certs/ ./traefik/certs/

# 7. Start services
./start.sh
```

## Monitoring Backups

### Check Backup Status

```bash
# View recent backup logs
tail -20 ~/selfhost/server/logs/postgres-backup.log
tail -20 ~/selfhost/server/logs/config-backup.log

# List B2 backups
rclone ls backblaze:${B2_BUCKET_NAME}/${B2_BACKUPS_PATH:-backups}/
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

Location: `<your-bucket>/${B2_BACKUPS_PATH:-backups}/`
- Offsite durability (11 nines)
- 30+ day retention
- Encrypted with keep-all-versions lifecycle
- Primary restore source for disasters

### Cleanup

Old backups are automatically cleaned up:
- Local: Deleted after 7 days
- B2: Deleted after 30 days (configurable)
