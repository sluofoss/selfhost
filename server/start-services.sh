#!/bin/bash

# Load environment variables
if [ -f /data/immich/.env ]; then
    export $(cat /data/immich/.env | xargs)
fi

# Ensure mount point exists
mkdir -p /data/immich/b2-mount

# Start rclone mount service if B2 is configured
if [ ! -z "$B2_APPLICATION_KEY_ID" ] && [ ! -z "$B2_APPLICATION_KEY" ]; then
    if ! systemctl is-active --quiet rclone-b2-mount; then
        echo "Starting Backblaze B2 mount..."
        sudo systemctl start rclone-b2-mount
        # Wait for mount to be ready
        sleep 5
    fi
    
    # Verify mount is working
    if mountpoint -q /data/immich/b2-mount; then
        echo "✓ Backblaze B2 mounted successfully"
    else
        echo "✗ Warning: Backblaze B2 mount not active"
    fi
fi

# Start BusyBox monitor if not running
if ! docker ps | grep -q busybox-monitor; then
  echo "Starting BusyBox monitor..."
  docker run -d --name busybox-monitor \
    --network immich-network \
    --restart always \
    busybox sh -c "while true; do sleep 60; echo 'Health check'; done"
fi

# Start Immich service if not running
if ! docker ps | grep -q immich; then
  echo "Starting Immich service..."
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
fi

echo ""
echo "=========================================="
echo "Services started successfully!"
echo ""
echo "Access Immich at: http://$(hostname -I | awk '{print $1}'):8080"
echo ""
echo "Storage Status:"
echo "  - Thumbnails: /data/immich/thumbnails (Local OCI volume)"
if mountpoint -q /data/immich/b2-mount; then
    echo "  - Photos: /data/immich/b2-mount (Backblaze B2 - Mounted)"
else
    echo "  - Photos: /data/immich/b2-mount (Local fallback)"
fi
echo "=========================================="
