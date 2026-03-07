# Daily Operations

## Quick Reference

```bash
# Start all services
cd ~/selfhost/server
./start.sh

# Check status (from each service directory)
cd traefik && docker compose ps
cd immich && docker compose ps

# Stop a stack
cd traefik && docker compose down

# Update images
cd immich && docker compose pull && docker compose up -d
```

## Starting Services

The `start.sh` script handles startup order:

1. **Traefik first** - Creates proxy network
2. **Monitoring** (optional) - If you answer "yes"
3. **Immich** - Application layer

```bash
cd ~/selfhost/server
./start.sh
```

## Checking Status

### View All Services

```bash
# In traefik directory
cd traefik && docker compose ps

# In immich directory
cd immich && docker compose ps
```

### View Logs

```bash
# All logs for a stack
docker compose logs

# Specific service
docker compose logs immich-server

# Follow logs (live)
docker compose logs -f immich-server

# Last 100 lines
docker compose logs --tail 100
```

## Stopping Services

```bash
# Stop specific stack
cd traefik && docker compose down
cd immich && docker compose down

# Stop everything
cd ~/selfhost/server
cd traefik && docker compose down
cd ../immich && docker compose down
cd ../monitoring && docker compose down
```

## Updating Services

### Update Images

```bash
cd immich
docker compose pull  # Download new images
docker compose up -d # Recreate containers
```

### Check for Updates

```bash
# See running versions
docker compose ps

# Check for newer images
docker compose pull --dry-run
```

## Common Tasks

### Restart a Service

```bash
cd immich
docker compose restart immich-server
```

### Enter a Container

```bash
# Get shell in immich container
docker exec -it immich_server sh

# Run commands inside container
docker exec immich_server ls -la /usr/src/app/upload
```

### Check Disk Space

```bash
# Container disk usage
docker system df

# Block volume usage
df -h /data

# Clean up unused images
docker image prune

# Clean up everything unused
docker system prune
```

### View Resource Usage

```bash
# Container stats (CPU, memory)
docker stats

# System-wide
htop
```

## Monitoring Health

### Check Service Health

```bash
# Traefik health
curl http://localhost:8080/ping

# Immich health
curl http://localhost:2283/api/server/ping
```

### Check Backups

```bash
# View recent backup logs
tail -f /var/log/postgres-backup.log
tail -f /var/log/config-backup.log

# Check B2 sync status
rclone ls backblaze:${B2_BUCKET_NAME}/${B2_BACKUPS_PATH:-backups}/
```

## Maintenance Tasks

### Weekly (Suggested)

```bash
# Check disk space
df -h

# Review logs for errors
docker compose logs | grep -i error

# Check backup status
ls -la /data/backups/
```

### Monthly (Suggested)

```bash
# Update all images
cd ~/selfhost/server
cd traefik && docker compose pull && docker compose up -d
cd ../immich && docker compose pull && docker compose up -d
cd ../monitoring && docker compose pull && docker compose up -d

# Review security updates
sudo apt update && sudo apt list --upgradable

# Clean up old Docker images
docker system prune -a
```

## Emergency Procedures

### Service Won't Start

```bash
# Check why
docker compose logs

# Check disk space
df -h

# Restart with force-recreate
docker compose up -d --force-recreate
```

### Out of Disk Space

```bash
# Find large files
du -sh /data/*
docker system df

# Clean Docker
docker system prune -a --volumes

# Clean old backups
find /data/backups -mtime +30 -delete
```

### Network Issues

```bash
# Check if proxy network exists
docker network ls

# Recreate if needed
docker network create proxy

# Check firewall
sudo ufw status
```
