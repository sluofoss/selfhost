#!/bin/bash

# Main start script for all services
# Starts infrastructure first, then applications

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo "======================================"
echo "Self-Hosted Infrastructure Startup"
echo "======================================"
echo ""

# Check if running from correct directory
if [ ! -d "$SCRIPT_DIR/traefik" ] || [ ! -d "$SCRIPT_DIR/immich" ]; then
    echo -e "${RED}Error:${NC} This script must be run from the server directory"
    echo "Expected directories: traefik/, immich/"
    exit 1
fi

# Function to check if docker compose is available
check_docker() {
    if ! command -v docker compose &> /dev/null; then
        echo -e "${RED}Error:${NC} Docker Compose not found"
        echo "Please install Docker Compose first"
        exit 1
    fi
}

# Function to start a service
start_service() {
    local service_name=$1
    local service_dir=$2
    
    echo ""
    echo -e "${YELLOW}Starting $service_name...${NC}"
    cd "$SCRIPT_DIR/$service_dir"
    
    if [ -f .env ]; then
        docker compose up -d
        echo -e "${GREEN}✓${NC} $service_name started"
    elif [ -f .env.example ]; then
        echo -e "${YELLOW}!${NC} $service_name has .env.example but no .env file"
        echo "  Please copy .env.example to .env and configure it"
        return 1
    else
        docker compose up -d
        echo -e "${GREEN}✓${NC} $service_name started"
    fi
    
    # Wait a moment for service to initialize
    sleep 2
}

# Check Docker is available
check_docker

# Function to generate Traefik routes from template
generate_traefik_routes() {
    local template_file="$SCRIPT_DIR/traefik/dynamic/routes.yml.template"
    local output_file="$SCRIPT_DIR/traefik/dynamic/routes.yml"
    
    if [ ! -f "$template_file" ]; then
        echo -e "${YELLOW}!${NC} Routes template not found, skipping route generation"
        return 0
    fi
    
    if [ ! -f "$SCRIPT_DIR/.env" ]; then
        echo -e "${RED}Error:${NC} Server .env file not found"
        exit 1
    fi
    
    # Source .env files to get DOMAIN and IMMICH_DOMAIN
    set -a
    source "$SCRIPT_DIR/.env"
    source "$SCRIPT_DIR/immich/.env"
    set +a
    
    # Generate routes.yml using envsubst
    if command -v envsubst &> /dev/null; then
        envsubst < "$template_file" > "$output_file"
        echo -e "${GREEN}✓${NC} Generated traefik/dynamic/routes.yml"
    else
        echo -e "${YELLOW}!${NC} envsubst not available, using sed as fallback"
        sed \
            -e "s|\${DOMAIN}|${DOMAIN}|g" \
            -e "s|\${IMMICH_DOMAIN}|${IMMICH_DOMAIN}|g" \
            "$template_file" > "$output_file"
        echo -e "${GREEN}✓${NC} Generated traefik/dynamic/routes.yml (sed)"
    fi
}

# Generate Traefik routes before starting
echo "Generating Traefik routes..."
generate_traefik_routes

# Step 1: Start Traefik (infrastructure layer)
echo "Step 1: Starting infrastructure (Traefik)..."
start_service "Traefik (Proxy)" "traefik"

# Verify proxy network exists
if ! docker network ls | grep -q "proxy"; then
    echo -e "${YELLOW}!${NC} Creating proxy network..."
    docker network create proxy
fi

# Step 2: Start Monitoring (optional infrastructure)
if [ -d "$SCRIPT_DIR/monitoring" ]; then
    echo ""
    read -p "Start monitoring services? (y/N): " start_monitoring
    if [[ $start_monitoring =~ ^[Yy]$ ]]; then
        start_service "Monitoring (Grafana + Prometheus)" "monitoring"
    else
        echo -e "${YELLOW}!${NC} Skipping monitoring"
    fi
fi

# Step 3: Start Immich (application layer)
echo ""
echo "Step 2: Starting application (Immich)..."
start_service "Immich" "immich"

# Step 4: Start Devtools (optional application layer)
if [ -d "$SCRIPT_DIR/devtools" ]; then
    echo ""
    read -p "Start devtools services? (y/N): " start_devtools
    if [[ $start_devtools =~ ^[Yy]$ ]]; then
        start_service "Devtools (code-server + Ollama + FileBrowser)" "devtools"
    else
        echo -e "${YELLOW}!${NC} Skipping devtools"
    fi
fi

echo ""
echo "======================================"
echo -e "${GREEN}All services started successfully!${NC}"
echo "======================================"
echo ""
echo "Access URLs:"
echo "  - Traefik Dashboard: http://$(hostname -I | awk '{print $1}'):8080"
echo "  - Immich:            https://photos.<your-domain> (requires DNS setup)"
echo "  - Grafana:           https://grafana.<your-domain> (if enabled)"
echo "  - code-server:       https://vscode.<your-domain> (if enabled)"
echo "  - FileBrowser:       https://files.<your-domain> (if enabled)"
echo ""
echo "Service Status:"
cd "$SCRIPT_DIR/traefik" && docker compose ps
echo ""
cd "$SCRIPT_DIR/immich" && docker compose ps
if [ -d "$SCRIPT_DIR/devtools" ] && [ -f "$SCRIPT_DIR/devtools/docker-compose.yml" ]; then
    echo ""
    cd "$SCRIPT_DIR/devtools" && docker compose ps
fi
echo ""
echo "To check logs:"
echo "  cd traefik && docker compose logs -f"
echo "  cd immich && docker compose logs -f"
echo ""
