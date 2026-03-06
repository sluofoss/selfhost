#!/bin/bash

# Comprehensive Setup Script for Self-Hosted Infrastructure
# Implements architecture from docs/architecture-and-strategy.md

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="/var/log/selfhost-setup.log"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Logging functions
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

log_success() {
    echo -e "${GREEN}[✓]${NC} $1" | tee -a "$LOG_FILE"
}

log_warning() {
    echo -e "${YELLOW}[!]${NC} $1" | tee -a "$LOG_FILE"
}

log_error() {
    echo -e "${RED}[✗]${NC} $1" | tee -a "$LOG_FILE"
}

# ==========================================
# CHECK PREREQUISITES
# ==========================================
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if running as root
    if [ "$EUID" -eq 0 ]; then
        log_error "Do not run this script as root"
        exit 1
    fi
    
    # Check Ubuntu version
    if ! grep -q "Ubuntu 22.04" /etc/os-release; then
        log_warning "This script is designed for Ubuntu 22.04 LTS"
    fi
    
    # Check available resources
    MEMORY_GB=$(free -g | awk '/^Mem:/{print $2}')
    if [ "$MEMORY_GB" -lt 20 ]; then
        log_warning "Less than 20GB RAM detected ($MEMORY_GB GB). Some services may not run optimally."
    fi
    
    log_success "Prerequisites check completed"
}

# ==========================================
# SYSTEM UPDATE & PACKAGES
# ==========================================
install_packages() {
    log "Installing required packages..."
    
    sudo apt-get update
    sudo apt-get install -y \
        apt-transport-https \
        ca-certificates \
        curl \
        gnupg \
        lsb-release \
        software-properties-common \
        rclone \
        fuse \
        apache2-utils \
        inotify-tools \
        cron
    
    log_success "Packages installed"
}

# ==========================================
# DOCKER INSTALLATION
# ==========================================
install_docker() {
    log "Installing Docker..."
    
    # Remove old versions
    sudo apt-get remove -y docker docker-engine docker.io containerd runc 2>/dev/null || true
    
    # Add Docker's official GPG key
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
    
    # Set up stable repository
    echo \
        "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu \
        $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
    
    # Install Docker Engine
    sudo apt-get update
    sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
    
    # Add user to docker group
    sudo usermod -aG docker $USER
    
    # Enable Docker service
    sudo systemctl enable docker
    sudo systemctl start docker
    
    log_success "Docker installed and configured"
    log_warning "You may need to logout and login again for Docker permissions to take effect"
}

# ==========================================
# DIRECTORY STRUCTURE
# ==========================================
create_directories() {
    log "Creating directory structure..."
    
    # Main data directories
    sudo mkdir -p /data/immich/{thumbnails,cache,b2-mount}
    sudo mkdir -p /data/backups/{postgres,configs,weekly}
    sudo mkdir -p /data/monitoring
    
    # Ensure ownership
    sudo chown -R $USER:$USER /data
    
    log_success "Directory structure created"
}

# ==========================================
# RCLONE & B2 CONFIGURATION
# ==========================================
configure_b2() {
    log "Configuring Backblaze B2..."
    
    # Check if .env exists
    if [ ! -f "$SCRIPT_DIR/.env" ]; then
        log_error ".env file not found! Please copy .env.example to .env and configure it."
        exit 1
    fi
    
    # Load environment variables
    set -a
    source "$SCRIPT_DIR/.env"
    set +a
    
    # Check B2 credentials
    if [ -z "$B2_APPLICATION_KEY_ID" ] || [ "$B2_APPLICATION_KEY_ID" = "your_key_id_here" ]; then
        log_warning "B2 credentials not configured. Skipping B2 mount setup."
        log_warning "You'll need to configure B2 manually later."
        return
    fi
    
    # Create rclone config
    mkdir -p ~/.config/rclone
    cat > ~/.config/rclone/rclone.conf << EOF
[backblaze]
type = b2
account = ${B2_APPLICATION_KEY_ID}
key = ${B2_APPLICATION_KEY}
hard_delete = false
EOF
    
    # Create systemd service for B2 mount
    sudo tee /etc/systemd/system/rclone-b2-mount.service > /dev/null << EOF
[Unit]
Description=RClone Backblaze B2 Mount
After=network-online.target
Wants=network-online.target

[Service]
Type=notify
Environment=RCLONE_CONFIG=/home/$USER/.config/rclone/rclone.conf
ExecStart=/usr/bin/rclone mount backblaze:${B2_PHOTOS_BUCKET:-immich-photos} /data/immich/b2-mount \\
    --allow-other \\
    --vfs-cache-mode writes \\
    --vfs-cache-max-size 10G \\
    --buffer-size 256M \\
    --dir-cache-time 72h \\
    --timeout 1h \\
    --umask 002
ExecStop=/bin/fusermount -uz /data/immich/b2-mount
Restart=on-failure
RestartSec=10
User=$USER

[Install]
WantedBy=multi-user.target
EOF
    
    # Reload and enable service
    sudo systemctl daemon-reload
    sudo systemctl enable rclone-b2-mount
    
    log_success "B2 configuration completed"
}

# ==========================================
# FIREWALL CONFIGURATION
# ==========================================
configure_firewall() {
    log "Configuring firewall..."
    
    # Install UFW if not present
    sudo apt-get install -y ufw
    
    # Default policies
    sudo ufw default deny incoming
    sudo ufw default allow outgoing
    
    # Allow SSH
    sudo ufw allow 22/tcp
    
    # Allow HTTP and HTTPS
    sudo ufw allow 80/tcp
    sudo ufw allow 443/tcp
    
    # Enable firewall (non-interactive)
    echo "y" | sudo ufw enable
    
    log_success "Firewall configured"
}

# ==========================================
# BACKUP CRON JOBS
# ==========================================
setup_cron() {
    log "Setting up backup cron jobs..."
    
    # Create cron entries
    (crontab -l 2>/dev/null || true; cat << EOF
# Self-Hosted Infrastructure Backups
# Daily database backup at 2:00 AM
0 2 * * * $SCRIPT_DIR/scripts/backup/backup-postgres.sh >> /var/log/postgres-backup.log 2>&1

# Hourly config backup
0 * * * * $SCRIPT_DIR/scripts/backup/backup-configs.sh >> /var/log/config-backup.log 2>&1

# Weekly full backup on Sundays at 3:00 AM
0 3 * * 0 $SCRIPT_DIR/scripts/backup/backup-weekly.sh >> /var/log/weekly-backup.log 2>&1
EOF
    ) | crontab -
    
    log_success "Cron jobs configured"
}

# ==========================================
# DOCKER COMPOSE SETUP
# ==========================================
setup_docker_compose() {
    log "Setting up Docker Compose services..."
    
    # Create proxy network (used by all services)
    docker network create proxy 2>/dev/null || true
    
    # Pull images for each service
    cd "$SCRIPT_DIR/../traefik"
    docker compose pull
    
    cd "$SCRIPT_DIR/../immich"
    docker compose pull
    
    if [ -d "$SCRIPT_DIR/../monitoring" ]; then
        cd "$SCRIPT_DIR/../monitoring"
        docker compose pull
    fi
    
    log_success "Docker Compose setup completed"
}

# ==========================================
# MAIN EXECUTION
# ==========================================
main() {
    log "======================================"
    log "Self-Hosted Infrastructure Setup"
    log "======================================"
    
    check_prerequisites
    install_packages
    install_docker
    create_directories
    configure_b2
    configure_firewall
    setup_cron
    setup_docker_compose
    
    log ""
    log "======================================"
    log_success "Setup completed successfully!"
    log "======================================"
    log ""
    log "Next steps:"
    log "  1. Configure your .env files:"
    log "     - cp .env.example .env"
    log "     - cp traefik/.env.example traefik/.env"
    log "     - cp immich/.env.example immich/.env"
    log "  2. Edit each .env file with your configuration"
    log "  3. Start services: ./start.sh"
    log "  4. Access services at:"
    log "     - Traefik Dashboard: http://$(hostname -I | awk '{print $1}'):8080"
    log "     - Immich: https://photos.<your-domain> (after DNS setup)"
    log ""
    log "  5. Set up your domain DNS to point to this server"
    log ""
    log "For more information, see docs/architecture-and-strategy.md"
}

# Run main function
main "$@"
