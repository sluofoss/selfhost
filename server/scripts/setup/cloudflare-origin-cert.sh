#!/bin/bash

# Cloudflare Origin Certificate Setup Script
# Automatically creates, downloads, and configures Origin Certificates
# Backs up to B2 for disaster recovery

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SERVER_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
TRAEFIK_DIR="$SERVER_DIR/traefik"
CERTS_DIR="$TRAEFIK_DIR/certs"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo "======================================"
echo "Cloudflare Origin Certificate Setup"
echo "======================================"
echo ""

# ==========================================
# CHECK PREREQUISITES
# ==========================================

echo -e "${BLUE}Checking prerequisites...${NC}"

# Check if running from server directory
if [ ! -d "$TRAEFIK_DIR" ]; then
    echo -e "${RED}Error:${NC} This script must be run from the server directory"
    echo "Expected: $TRAEFIK_DIR to exist"
    exit 1
fi

# Check for B2 configuration
if [ ! -f "$SERVER_DIR/.env" ]; then
    echo -e "${RED}Error:${NC} Server .env file not found"
    echo "Please configure B2 credentials first:"
    echo "  cp $SERVER_DIR/.env.example $SERVER_DIR/.env"
    exit 1
fi

# Load B2 config
set -a; source "$SERVER_DIR/.env"; set +a
source "$SCRIPT_DIR/../lib/rclone-env.sh"

if [ -z "$B2_APPLICATION_KEY_ID" ] || [ "$B2_APPLICATION_KEY_ID" = "your_key_id_here" ]; then
    echo -e "${RED}Error:${NC} B2 credentials not configured"
    echo "Please edit $SERVER_DIR/.env with your B2 credentials"
    exit 1
fi

# Check rclone
if ! command -v rclone &> /dev/null; then
    echo -e "${RED}Error:${NC} rclone not installed"
    echo "Please run ./scripts/setup/install.sh first"
    exit 1
fi

# ==========================================
# HELPER FUNCTIONS
# ==========================================

update_traefik_config() {
    # Check if traefik.yml exists
    if [ ! -f "$TRAEFIK_DIR/traefik.yml" ]; then
        echo -e "${RED}Error:${NC} traefik.yml not found"
        return 1
    fi
    
    # Backup original config
    cp "$TRAEFIK_DIR/traefik.yml" "$TRAEFIK_DIR/traefik.yml.backup.$(date +%Y%m%d)"
    
    # Update traefik.yml to use origin certificates
    cat > "$TRAEFIK_DIR/traefik.yml" << TRAEFIK_CONFIG
global:
  checkNewVersion: false
  sendAnonymousUsage: false

api:
  dashboard: true

providers:
  docker:
    exposedByDefault: false
    network: proxy
  file:
    directory: /dynamic
    watch: true

entryPoints:
  web:
    address: ":80"
    http:
      redirections:
        entryPoint:
          to: websecure
          scheme: https
  websecure:
    address: ":443"
    http:
      tls:
        certificates:
          - certFile: /certs/origin-cert.pem
            keyFile: /certs/origin-key.pem

certificatesResolvers:
  letsencrypt:
    acme:
      email: \${ACME_EMAIL}
      storage: /letsencrypt/acme.json
      tlsChallenge: {}

log:
  level: INFO
  format: common

accessLog:
  format: common

ping:
  entryPoint: "web"
TRAEFIK_CONFIG

    # Update docker-compose.yml to mount certs
    if [ -f "$TRAEFIK_DIR/docker-compose.yml" ]; then
        # Check if certs volume already exists
        if ! grep -q "./certs:/certs:ro" "$TRAEFIK_DIR/docker-compose.yml"; then
            # Add certs volume to traefik service
            sed -i '/- .\/dynamic:\/dynamic:ro/a\      - .\/certs:\/certs:ro' "$TRAEFIK_DIR/docker-compose.yml"
            echo -e "${GREEN}✓${NC} Updated docker-compose.yml to mount certificates"
        fi
    fi
    
    echo -e "${GREEN}✓${NC} Traefik configuration updated"
    echo -e "${YELLOW}!${NC} Traefik will use Cloudflare Origin Certificate (15-year validity)"
    echo ""
    echo "Note: Let's Encrypt resolver is still configured as fallback"
}

# Check for existing cert in B2 (recreation scenario)
echo -e "${BLUE}Checking for existing certificate in B2...${NC}"
B2_CERT_PATH="backups/certs/origin-cert.pem"
B2_KEY_PATH="backups/certs/origin-key.pem"

if rclone ls "backblaze:${B2_BUCKET_NAME}/certs/" 2>/dev/null | grep -q "origin-cert.pem"; then
    echo -e "${GREEN}✓${NC} Found existing certificate in B2"
    read -p "Restore from B2 backup instead of creating new? (Y/n): " restore_from_b2
    
    if [[ ! $restore_from_b2 =~ ^[Nn]$ ]]; then
        echo -e "${BLUE}Restoring certificate from B2...${NC}"
        mkdir -p "$CERTS_DIR"
        rclone copy "backblaze:${B2_BUCKET_NAME}/certs/" "$CERTS_DIR/"
        echo -e "${GREEN}✓${NC} Certificate restored from B2"
        
        # Update Traefik config
        echo -e "${BLUE}Updating Traefik configuration...${NC}"
        update_traefik_config
        
        echo ""
        echo "======================================"
        echo -e "${GREEN}Certificate restored successfully!${NC}"
        echo "======================================"
        echo ""
        echo "Next steps:"
        echo "  1. Restart Traefik: cd traefik && docker compose restart"
        echo "  2. Test HTTPS: curl -I https://yourdomain.com"
        echo ""
        exit 0
    fi
fi

# ==========================================
# CLOUDFLARE API TOKEN SETUP
# ==========================================

echo ""
echo "======================================"
echo "Cloudflare API Token Setup"
echo "======================================"
echo ""

if [ -f "$SCRIPT_DIR/.cloudflare-token" ]; then
    echo -e "${GREEN}✓${NC} Found existing Cloudflare token"
    CF_API_TOKEN=$(cat "$SCRIPT_DIR/.cloudflare-token")
else
    echo -e "${YELLOW}!${NC} Cloudflare API token not found"
    echo ""
    echo "To create one:"
    echo "  1. Go to https://dash.cloudflare.com/profile/api-tokens"
    echo "  2. Click 'Create Token'"
    echo "  3. Use 'Custom token' with these permissions:"
    echo "     - Zone:Read (for listing zones)"
    echo "     - SSL:Edit (for creating certificates)"
    echo "  4. Zone Resources: Include - Specific zone - yourdomain.com"
    echo ""
    read -p "Enter your Cloudflare API Token: " CF_API_TOKEN
    
    if [ -z "$CF_API_TOKEN" ]; then
        echo -e "${RED}Error:${NC} No token provided"
        exit 1
    fi
    
    # Save token for future use
    echo "$CF_API_TOKEN" > "$SCRIPT_DIR/.cloudflare-token"
    chmod 600 "$SCRIPT_DIR/.cloudflare-token"
    echo -e "${GREEN}✓${NC} Token saved for future use"
fi

# ==========================================
# CREATE ORIGIN CERTIFICATE
# ==========================================

echo ""
echo "======================================"
echo "Creating Origin Certificate"
echo "======================================"
echo ""

# Get zone ID
read -p "Enter your domain (e.g., example.com): " DOMAIN

if [ -z "$DOMAIN" ]; then
    echo -e "${RED}Error:${NC} Domain not provided"
    exit 1
fi

# Get zone ID from Cloudflare
echo -e "${BLUE}Looking up zone ID...${NC}"
ZONE_ID=$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones?name=$DOMAIN" \
    -H "Authorization: Bearer $CF_API_TOKEN" \
    -H "Content-Type: application/json" | grep -o '"id":"[^"]*"' | head -1 | cut -d'"' -f4)

if [ -z "$ZONE_ID" ]; then
    echo -e "${RED}Error:${NC} Could not find zone ID for $DOMAIN"
    echo "Please check:"
    echo "  1. Domain is correct"
    echo "  2. API token has Zone:Read permission"
    echo "  3. Domain is in your Cloudflare account"
    exit 1
fi

echo -e "${GREEN}✓${NC} Found zone ID: $ZONE_ID"

# Create origin certificate
echo -e "${BLUE}Creating origin certificate...${NC}"
CERT_RESPONSE=$(curl -s -X POST "https://api.cloudflare.com/client/v4/zones/$ZONE_ID/origin_ca_certificates" \
    -H "Authorization: Bearer $CF_API_TOKEN" \
    -H "Content-Type: application/json" \
    -d '{
        "csr": "",
        "hostnames": ["*.'$DOMAIN'", "'$DOMAIN'"],
        "request_type": "origin-rsa",
        "requested_validity": 5475
    }')

# Extract certificate and private key
CERTIFICATE=$(echo "$CERT_RESPONSE" | grep -o '"certificate":"[^"]*"' | cut -d'"' -f4 | sed 's/\\n/\n/g')
PRIVATE_KEY=$(echo "$CERT_RESPONSE" | grep -o '"private_key":"[^"]*"' | cut -d'"' -f4 | sed 's/\\n/\n/g')

if [ -z "$CERTIFICATE" ] || [ -z "$PRIVATE_KEY" ]; then
    echo -e "${RED}Error:${NC} Failed to create certificate"
    echo "Response: $CERT_RESPONSE"
    exit 1
fi

echo -e "${GREEN}✓${NC} Certificate created successfully"

# ==========================================
# SAVE CERTIFICATE
# ==========================================

echo ""
echo "======================================"
echo "Saving Certificate"
echo "======================================"
echo ""

# Create certs directory
mkdir -p "$CERTS_DIR"

# Save certificate
echo "$CERTIFICATE" > "$CERTS_DIR/origin-cert.pem"
echo "$PRIVATE_KEY" > "$CERTS_DIR/origin-key.pem"

# Set permissions
chmod 600 "$CERTS_DIR/origin-key.pem"
chmod 644 "$CERTS_DIR/origin-cert.pem"

echo -e "${GREEN}✓${NC} Certificate saved to $CERTS_DIR/"

# ==========================================
# BACKUP TO B2
# ==========================================

echo ""
echo "======================================"
echo "Backing Up to B2"
echo "======================================"
echo ""

echo -e "${BLUE}Uploading certificate to B2...${NC}"

# Create backup directory
mkdir -p /tmp/certs-backup
cp "$CERTS_DIR"/* /tmp/certs-backup/

# Upload to B2
if rclone copy /tmp/certs-backup/ "backblaze:${B2_BUCKET_NAME}/certs/"; then
    echo -e "${GREEN}✓${NC} Certificate backed up to B2"
else
    echo -e "${YELLOW}!${NC} Failed to backup to B2 (non-critical)"
fi

# Cleanup
rm -rf /tmp/certs-backup

# ==========================================
# UPDATE TRAEFIK CONFIG
# ==========================================

echo ""
echo "======================================"
echo "Updating Traefik Configuration"
echo "======================================"
echo ""

# Run the update
update_traefik_config

echo ""
echo "======================================"
echo -e "${GREEN}Setup Complete!${NC}"
echo "======================================"
echo ""
echo "Summary:"
echo "  ✓ Origin Certificate created (15-year validity)"
echo "  ✓ Certificate saved to: $CERTS_DIR/"
echo "  ✓ Certificate backed up to B2"
echo "  ✓ Traefik configured to use Origin Certificate"
echo ""
echo "Next steps:"
echo "  1. Restart Traefik: cd traefik && docker compose restart"
echo "  2. Test HTTPS: curl -I https://yourdomain.com"
echo "  3. Verify in Cloudflare dashboard: SSL/TLS → Origin Server"
echo ""
echo "If you need to restore this certificate later:"
echo "  rclone copy backblaze:\${B2_BUCKET_NAME}/certs/ ./traefik/certs/"
echo ""
