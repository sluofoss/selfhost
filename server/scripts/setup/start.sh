#!/bin/bash

# Quick start script for self-hosted infrastructure
# Usage: ./start.sh

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "======================================"
echo "Starting Self-Hosted Infrastructure"
echo "======================================"
echo ""

# Check if docker compose is available
if ! command -v docker compose &> /dev/null; then
    echo "Error: Docker Compose not found"
    echo "Please run ./scripts/setup/install.sh first"
    exit 1
fi

# Check if .env exists
if [ ! -f "$SCRIPT_DIR/../.env" ]; then
    echo "Error: .env file not found"
    echo "Please copy .env.example to .env and configure it"
    exit 1
fi

# Load environment
set -a
source "$SCRIPT_DIR/../.env"
set +a

# Start B2 mount if configured
if [ ! -z "$B2_APPLICATION_KEY_ID" ] && [ "$B2_APPLICATION_KEY_ID" != "your_key_id_here" ]; then
    echo "Starting Backblaze B2 mount..."
    sudo systemctl start rclone-b2-mount 2>/dev/null || true
    sleep 5
    
    if mountpoint -q /data/immich/b2-mount; then
        echo "✓ B2 mount active"
    else
        echo "⚠ B2 mount not active (this is OK if not configured)"
    fi
fi

# Start Docker services
echo ""
echo "Starting Docker services..."
cd "$SCRIPT_DIR/.."
docker compose up -d

echo ""
echo "======================================"
echo "Services started successfully!"
echo "======================================"
echo ""
echo "Access URLs:"
echo "  - Traefik Dashboard: http://$(hostname -I | awk '{print $1}'):8080"
echo "  - Immich: https://photos.${DOMAIN} (requires DNS setup)"
echo "  - Grafana: https://grafana.${DOMAIN} (requires DNS setup)"
echo ""
echo "To check service status: docker compose ps"
echo "To view logs: docker compose logs -f [service-name]"
echo ""
