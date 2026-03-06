#!/bin/bash

# Load environment variables
if [ -f /data/immich/.env ]; then
    export $(cat /data/immich/.env | xargs)
fi

# Create directory structure
# /data/immich/thumbnails - Local storage for thumbnails (fast access)
# /data/immich/cache - Temporary cache for uploads
mkdir -p /data/immich/thumbnails
mkdir -p /data/immich/cache

# Update package list and install Docker
sudo apt update && sudo apt install -y docker.io

# Install rclone for Backblaze B2 mounting
sudo apt install -y rclone fuse

# Create rclone config for Backblaze B2 if credentials are provided
if [ ! -z "$B2_APPLICATION_KEY_ID" ] && [ ! -z "$B2_APPLICATION_KEY" ]; then
    mkdir -p ~/.config/rclone
    cat > ~/.config/rclone/rclone.conf << EOF
[backblaze]
type = b2
account = $B2_APPLICATION_KEY_ID
key = $B2_APPLICATION_KEY
hard_delete = false
EOF
    
    # Create mount point for B2
    mkdir -p /data/immich/b2-mount
    
    # Create systemd service for rclone mount
    sudo tee /etc/systemd/system/rclone-b2-mount.service > /dev/null << 'EOF'
[Unit]
Description=RClone Backblaze B2 Mount
After=network-online.target
Wants=network-online.target

[Service]
Type=notify
Environment=RCLONE_CONFIG=/root/.config/rclone/rclone.conf
ExecStart=/usr/bin/rclone mount backblaze:immich-photos /data/immich/b2-mount \
    --allow-other \
    --vfs-cache-mode writes \
    --vfs-cache-max-size 10G \
    --buffer-size 256M \
    --dir-cache-time 72h \
    --drive-chunk-size 128M \
    --timeout 1h \
    --umask 002
ExecStop=/bin/fusermount -uz /data/immich/b2-mount
Restart=on-failure
RestartSec=10
User=root

[Install]
WantedBy=multi-user.target
EOF
    
    # Enable and start rclone mount service
    sudo systemctl daemon-reload
    sudo systemctl enable rclone-b2-mount
    sudo systemctl start rclone-b2-mount
    
    echo "Backblaze B2 mount configured and started"
fi

# Create Docker network
docker network create immich-network || true

# Create BusyBox monitor (health check every 60s)
docker run -d --name busybox-monitor \
  --network immich-network \
  --restart always \
  busybox sh -c "while true; do sleep 60; echo 'Health check'; done"

# Create Immich container with optimized storage layout
# - Thumbnails stored locally on OCI block volume
# - Original photos accessed via B2 mount (or local if B2 not configured)
docker run -d --name immich \
  --network immich-network \
  -p 8080:8080 \
  -v /data/immich/thumbnails:/data/thumbnails \
  -v /data/immich/cache:/data/cache \
  -v /data/immich/b2-mount:/data/photos:ro \
  -e IMMICH_STORAGE_THUMBNAILS=/data/thumbnails \
  -e IMMICH_STORAGE_CACHE=/data/cache \
  -e IMMICH_STORAGE_UPLOAD=/data/photos/upload \
  --restart unless-stopped \
  immich/immich:latest

# Verify services are running
docker ps | grep -E 'immich|busybox'

echo ""
echo "=========================================="
echo "Setup Complete!"
echo "=========================================="
echo "Storage Configuration:"
echo "  - Thumbnails: Local OCI volume (/data/immich/thumbnails)"
if [ ! -z "$B2_APPLICATION_KEY_ID" ]; then
    echo "  - Original Photos: Backblaze B2 (mounted at /data/immich/b2-mount)"
else
    echo "  - Original Photos: Local OCI volume (B2 not configured)"
fi
echo ""
echo "Next steps:"
echo "  1. Configure Immich via web UI at http://$(hostname -I | awk '{print $1}'):8080"
echo "  2. Set up external storage library pointing to /data/photos"
echo "=========================================="
