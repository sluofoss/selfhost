#!/bin/bash

# Terraform/OpenTofu Apply Wrapper with B2 State Backup
# This script wraps 'tofu apply' and automatically backs up state to B2

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SERVER_DIR="$(cd "$SCRIPT_DIR/../server" && pwd)"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo "======================================"
echo "Terraform Apply with B2 State Backup"
echo "======================================"
echo ""

# Check if we're in the infra directory
if [ ! -f "$SCRIPT_DIR/main.tf" ]; then
    echo -e "${RED}Error:${NC} This script must be run from the infra/ directory"
    echo "Current directory: $(pwd)"
    exit 1
fi

# Load B2 configuration
if [ -f "$SERVER_DIR/.env" ]; then
    source "$SERVER_DIR/.env"
fi

# Check B2 credentials
if [ -z "$B2_APPLICATION_KEY_ID" ] || [ "$B2_APPLICATION_KEY_ID" = "your_key_id_here" ]; then
    echo -e "${RED}Error:${NC} B2 credentials not configured"
    echo "Please configure B2 in $SERVER_DIR/.env"
    exit 1
fi

# Check rclone
if ! command -v rclone &> /dev/null; then
    echo -e "${RED}Error:${NC} rclone not installed"
    echo "Please run ./server/scripts/setup/install.sh first"
    exit 1
fi

# Show current state info
echo -e "${BLUE}Current State:${NC}"
if [ -f "terraform.tfstate" ]; then
    echo "  Local state file: $(ls -lh terraform.tfstate | awk '{print $5}')"
    echo "  Last modified: $(stat -c %y terraform.tfstate 2>/dev/null || stat -f %Sm terraform.tfstate 2>/dev/null)"
else
    echo "  No local state file found (fresh setup?)"
fi
echo ""

# Backup current state before apply (local backup)
if [ -f "terraform.tfstate" ]; then
    TIMESTAMP=$(date +%Y%m%d_%H%M%S)
    cp terraform.tfstate "terraform.tfstate.backup.${TIMESTAMP}"
    echo -e "${GREEN}✓${NC} Local backup created: terraform.tfstate.backup.${TIMESTAMP}"
fi

echo ""
echo "======================================"
echo "Running: tofu apply $@"
echo "======================================"
echo ""

# Run tofu apply with all passed arguments
if tofu apply "$@"; then
    echo ""
    echo -e "${GREEN}✓${NC} Apply completed successfully"
    
    # Backup to B2
    echo ""
    echo "======================================"
    echo "Backing up state to B2..."
    echo "======================================"
    
    TIMESTAMP=$(date +%Y%m%d_%H%M%S)
    B2_BUCKET="${B2_BUCKET_NAME:-sluo-personal-b2}"
    
    # Create temp directory for backup
    TEMP_DIR=$(mktemp -d)
    cp terraform.tfstate "$TEMP_DIR/"
    
    # Copy with timestamp (versioned backup)
    echo -e "${BLUE}Uploading versioned backup...${NC}"
    if rclone copy "$TEMP_DIR/terraform.tfstate" "backblaze:${B2_BUCKET}/terraform/terraform.tfstate.${TIMESTAMP}"; then
        echo -e "${GREEN}✓${NC} Versioned backup: terraform/terraform.tfstate.${TIMESTAMP}"
    else
        echo -e "${RED}✗${NC} Failed to upload versioned backup"
    fi
    
    # Copy as "latest"
    echo -e "${BLUE}Updating latest backup...${NC}"
    if rclone copy "$TEMP_DIR/terraform.tfstate" "backblaze:${B2_BUCKET}/terraform/terraform.tfstate.latest"; then
        echo -e "${GREEN}✓${NC} Latest backup: terraform/terraform.tfstate.latest"
    else
        echo -e "${RED}✗${NC} Failed to upload latest backup"
    fi
    
    # Cleanup temp
    rm -rf "$TEMP_DIR"
    
    # Cleanup old local backups (keep last 10)
    ls -t terraform.tfstate.backup.* 2>/dev/null | tail -n +11 | xargs -r rm
    
    echo ""
    echo "======================================"
    echo -e "${GREEN}State backup completed!${NC}"
    echo "======================================"
    echo ""
    echo "Backup locations:"
    echo "  - B2: ${B2_BUCKET}/terraform/terraform.tfstate.${TIMESTAMP}"
    echo "  - B2: ${B2_BUCKET}/terraform/terraform.tfstate.latest"
    echo "  - Local: terraform.tfstate.backup.${TIMESTAMP}"
    echo ""
    echo "To restore from B2:"
    echo "  rclone copy backblaze:${B2_BUCKET}/terraform/terraform.tfstate.latest ./terraform.tfstate"
    echo ""
    
else
    echo ""
    echo -e "${RED}✗${NC} Apply failed - state not backed up to B2"
    echo "Local backup preserved: terraform.tfstate.backup.${TIMESTAMP}"
    exit 1
fi
