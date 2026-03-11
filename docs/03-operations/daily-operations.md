# Daily Operations

## Quick Reference

If you need to recover the current reserved OCI IP before you SSH in, run this from your local repo checkout (not on the server):

```bash
cd infra
tofu output -raw instance_public_ip
tofu output -raw ssh_command
```

All commands in this document are intended to be run on the OCI host after you SSH in.

```bash
# Start all services
cd ~/selfhost/server
./start.sh

# Check status (from each service directory)
cd traefik && docker compose ps
cd immich && docker compose ps
cd ../devtools && docker compose ps

# Stop a stack
cd traefik && docker compose down

# Update images
cd immich && docker compose pull && docker compose up -d
cd ../devtools && docker compose pull && docker compose up -d
```

## Starting Services

The `start.sh` script handles startup order:

1. **Traefik first** - Creates proxy network
2. **Monitoring** (optional) - If you answer "yes"
3. **Immich** - Application layer
4. **Devtools** (optional) - If you answer "yes"

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

# In devtools directory
cd ../devtools && docker compose ps
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
cd ../devtools && docker compose down

# Stop everything
cd ~/selfhost/server
cd traefik && docker compose down
cd ../immich && docker compose down
cd ../monitoring && docker compose down
cd ../devtools && docker compose down
```

## Updating Services

### Update Images

```bash
cd immich
docker compose pull  # Download new images
docker compose up -d # Recreate containers

cd ../devtools
docker compose pull
docker compose up -d
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

# Check the main Option 1 storage surfaces
du -sh /data/immich/postgres /data/immich/thumbnails /data/immich/ml-cache /data/immich/rclone-cache /data/backups/*

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

# Ollama health (internal-only)
cd ~/selfhost/server/devtools
docker compose exec ollama ollama list
```

### Check Backups

```bash
# View recent backup logs
tail -f ~/selfhost/server/logs/postgres-backup.log
tail -f ~/selfhost/server/logs/config-backup.log

# Check B2 sync status
rclone ls backblaze:${B2_BUCKET_NAME}/${B2_BACKUPS_PATH:-backups}/
```

## Maintenance Tasks

### Weekly (Suggested)

```bash
# Check disk space
df -h

# Check the biggest Immich-local paths
du -sh /data/immich/postgres /data/immich/thumbnails /data/immich/ml-cache /data/immich/rclone-cache /data/backups/*

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
cd ../devtools && docker compose pull && docker compose up -d

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

# Reclaim rebuildable preview JPEGs first
find /data/immich/thumbnails -type f -name '*_preview.jpeg' -delete

# Clean Docker
docker system prune -a --volumes

# Clean expired weekly snapshots if needed
find /data/backups/weekly -mindepth 1 -maxdepth 1 -mtime +28 -exec rm -rf {} \;
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
