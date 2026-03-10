# Troubleshooting Guide

## Quick Diagnostics

```bash
# Check everything is running
cd ~/selfhost/server/traefik && docker compose ps
cd ~/selfhost/server/immich && docker compose ps

# Check recent errors
docker compose logs --tail 50 | grep -i error

# Check system resources
free -h && df -h

# Check cloud-init status (first boot only)
cloud-init status
sudo cat /var/log/cloud-init-output.log
```

## Common Issues

### Services Won't Start

**Symptom**: `docker compose up` fails or containers keep restarting

**Check**:
```bash
# View logs
docker compose logs

# Check disk space
df -h

# Check if .env files exist
ls -la .env traefik/.env immich/.env
```

**Solutions**:

1. **Missing .env file**
   ```bash
   cp .env.example .env
   # Edit with your values
   ```

2. **Disk full**
   ```bash
   # Clean old backups
   find /data/backups -mtime +7 -delete
   
   # Clean Docker
   docker system prune
   ```

3. **Port already in use**
   ```bash
   # Find what's using port 80/443
   sudo netstat -tlnp | grep ':80'
   
   # Stop conflicting service
   sudo systemctl stop apache2 nginx
   ```

### SSL Certificate Issues

**Symptom**: HTTPS not working, certificate errors

**Check**:
```bash
# Check Traefik logs
cd traefik && docker compose logs

# Verify DNS resolves
dig photos.yourdomain.com

# Check Let's Encrypt rate limits
# https://letsencrypt.org/docs/rate-limits/
```

**Solutions**:

1. **DNS not propagated**
   - Wait 5-10 minutes after DNS changes
   - Use `dig` or `nslookup` to verify

2. **Port 80 blocked**
   ```bash
   sudo ufw allow 80/tcp
   sudo ufw allow 443/tcp
   ```

3. **Rate limited**
   - Wait 1 hour and try again
   - Or use staging server for testing:
     ```yaml
     # In traefik.yml
     - --certificatesresolvers.letsencrypt.acme.caserver=https://acme-staging-v02.api.letsencrypt.org/directory
     ```

### B2 Mount Not Working

**Symptom**: Photos not appearing, mount point empty

**Check**:
```bash
# Check if mounted
mountpoint -q /data/immich/b2-mount && echo "Mounted" || echo "Not mounted"

# Check rclone service
sudo systemctl status rclone-b2-mount

# Test rclone directly
rclone ls backblaze:${B2_BUCKET_NAME}/${B2_PHOTOS_PATH:-photos}/
```

**Solutions**:

1. **Rclone not configured**
   ```bash
   # Test connection (uses env vars, not rclone.conf)
   rclone ls backblaze:${B2_BUCKET_NAME}/
   ```

2. **Mount service not running**
   ```bash
   sudo systemctl start rclone-b2-mount
   sudo systemctl enable rclone-b2-mount
   ```

3. **FUSE not available**
   ```bash
   sudo apt install fuse
   ```

### Immich Won't Upload Photos

**Symptom**: Uploads fail or hang

**Check**:
```bash
# Check Immich logs
cd immich && docker compose logs immich-server

# Check B2 mount
df -h /data/immich/b2-mount

# Check disk space on thumbnails volume
df -h /data/immich/thumbnails
```

**Solutions**:

1. **B2 mount not available**
   - See B2 Mount section above

2. **Thumbnails volume full**
   ```bash
   # Check usage
   du -sh /data/immich/thumbnails/*
   
   # Clean old thumbnails (Immich will regenerate)
   find /data/immich/thumbnails -mtime +30 -delete
   ```

3. **Database issues**
   ```bash
   # Check postgres logs
   docker compose logs database
   
   # Check postgres is healthy
   docker exec immich_postgres pg_isready -U postgres
   
   # Restart database
   docker compose restart database
   ```

### Can't Access Web UI

**Symptom**: Browser can't connect to services

**Check**:
```bash
# Check if Traefik is running
cd traefik && docker compose ps

# Check if services are healthy
docker compose ps

# Test locally
curl http://localhost:8080  # Traefik dashboard
curl http://localhost:2283  # Immich
```

**Solutions**:

1. **Traefik not running**
   ```bash
   cd traefik
   docker compose up -d
   ```

2. **Firewall blocking**
   ```bash
   sudo ufw status
   sudo ufw allow 80/tcp
   sudo ufw allow 443/tcp
   ```

3. **Wrong domain configured**
   - Check `.env` files have correct DOMAIN
   - Verify DNS A records point to server IP

### Backup Failures

**Symptom**: Backups not appearing in B2

**Check**:
```bash
# Check backup logs
tail -f ~/selfhost/server/logs/postgres-backup.log

# Test rclone B2 connection
rclone ls backblaze:${B2_BUCKET_NAME}/${B2_BACKUPS_PATH:-backups}/

# Check cron jobs
crontab -l
```

**Solutions**:

1. **Cron not running**
   ```bash
   # Check cron service
   sudo systemctl status cron
   
   # Re-run install.sh to reinstall cron jobs
   ./scripts/setup/install.sh
   ```

2. **B2 credentials invalid**
   ```bash
   # Verify .env has correct B2 credentials
   cat .env | grep B2_
   
   # Test connection
   rclone ls backblaze:${B2_BUCKET_NAME}/
   ```

3. **Backup script errors**
   ```bash
   # Run manually to see errors
   ./scripts/backup/backup-postgres.sh
   ```

### Block Volume Issues

**Symptom**: `/data` directory missing or not writable

**Check**:
```bash
# Check mount
df -h /data
lsblk

# Check fstab
cat /etc/fstab | grep data
```

**Solutions**:

1. **Volume not mounted**
   ```bash
   sudo mount -a
   ```

2. **Volume not formatted** (fresh instance)
   ```bash
   # Cloud-init should handle this, but if it didn't:
   # Find the device (usually /dev/sdb)
   lsblk
   sudo mkfs.ext4 /dev/sdb
   sudo mount /dev/sdb /data
   ```

## Getting Help

1. **Check logs first**: `docker compose logs`
2. **Check cloud-init logs**: `sudo cat /var/log/cloud-init-output.log`
3. **Search issues**: Check GitHub issues for similar problems
4. **System info**: Include output of `docker compose ps` and `docker compose logs` when asking for help

## Debug Mode

Enable debug logging:

```bash
# Traefik debug
cd traefik
docker compose down
# Edit docker-compose.yml, change --log.level=INFO to --log.level=DEBUG
docker compose up -d

# Immich debug
# Check Immich docs for debug environment variables
```
