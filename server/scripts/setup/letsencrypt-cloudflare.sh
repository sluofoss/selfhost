#!/bin/bash

# Cloudflare API token setup for Traefik DNS-01 certificate challenge
#
# Traefik is already configured to use DNS-01 via Cloudflare (traefik.yml +
# docker-compose.yml). This script's only job is to write CF_DNS_API_TOKEN
# into traefik/.env so that Traefik can call the Cloudflare API at runtime.
#
# Run this once on a fresh deployment. After restarting Traefik, certificates
# are issued and renewed automatically — no further action needed.

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SERVER_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
TRAEFIK_DIR="$SERVER_DIR/traefik"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo "======================================"
echo "Cloudflare DNS Token Setup"
echo "======================================"
echo ""

# Require traefik/.env to exist first
if [ ! -f "$TRAEFIK_DIR/.env" ]; then
    echo -e "${RED}Error:${NC} traefik/.env not found"
    echo "Please copy traefik/.env.example to traefik/.env and fill in DOMAIN, ACME_EMAIL, etc."
    exit 1
fi

# Load .env to read DOMAIN for display
set -a; source "$TRAEFIK_DIR/.env"; set +a

# Check whether the token is already configured and non-placeholder
if grep -q "^CF_DNS_API_TOKEN=" "$TRAEFIK_DIR/.env" \
   && ! grep -q "your_cloudflare_api_token_here" "$TRAEFIK_DIR/.env"; then
    echo -e "${GREEN}✓${NC} CF_DNS_API_TOKEN is already configured in traefik/.env"
    echo ""
    echo "To update the token, edit traefik/.env directly and restart Traefik."
    exit 0
fi

echo -e "${BLUE}Domain:${NC} ${DOMAIN:-<not set>}"
echo ""
echo "Traefik uses DNS-01 to automatically get and renew HTTPS certificates."
echo "This requires a Cloudflare API token with permission to edit DNS records."
echo "(Let's Encrypt temporarily creates a DNS TXT record to verify you own the domain.)"
echo ""
echo "Steps to create the token:"
echo "  1. Go to: https://dash.cloudflare.com/profile/api-tokens"
echo "  2. Click 'Create Token' → 'Custom Token'"
echo "  3. Set permissions:  Zone / DNS / Edit"
echo "  4. Set zone resources: Include / Specific zone / $DOMAIN"
echo "  5. Click 'Continue to summary', then 'Create Token'"
echo "  6. Copy the token — you can only see it once"
echo ""
read -rp "Paste your Cloudflare API token: " CF_TOKEN

if [ -z "$CF_TOKEN" ]; then
    echo -e "${RED}Error:${NC} Token cannot be empty"
    exit 1
fi

# Write or replace CF_DNS_API_TOKEN in traefik/.env
if grep -q "^CF_DNS_API_TOKEN=" "$TRAEFIK_DIR/.env"; then
    # Replace existing line (handles placeholder value too)
    sed -i "s|^CF_DNS_API_TOKEN=.*|CF_DNS_API_TOKEN=$CF_TOKEN|" "$TRAEFIK_DIR/.env"
else
    # Append to file
    echo "" >> "$TRAEFIK_DIR/.env"
    echo "# Cloudflare API token for DNS-01 certificate challenge (auto HTTPS)" >> "$TRAEFIK_DIR/.env"
    echo "CF_DNS_API_TOKEN=$CF_TOKEN" >> "$TRAEFIK_DIR/.env"
fi

echo -e "${GREEN}✓${NC} CF_DNS_API_TOKEN saved to traefik/.env"
echo ""
echo "======================================"
echo -e "${GREEN}Done!${NC}"
echo "======================================"
echo ""
echo "Next steps:"
echo "  1. Restart Traefik:   cd server/traefik && docker compose restart"
echo "  2. Watch cert issuance (should see ACME entries within ~2 minutes):"
echo "     docker logs -f traefik 2>&1 | grep -i acme"
echo ""
echo "Certificates are stored in:  server/traefik/letsencrypt/acme.json"
echo "Validity: 90 days — Traefik renews automatically 30 days before expiry."
echo "No further action needed."
echo ""
