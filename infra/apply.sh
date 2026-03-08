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

# Pre-flight checks
echo -e "${BLUE}Pre-flight checks:${NC}"

# Check if OpenTofu is installed
if ! command -v tofu &> /dev/null; then
    echo -e "${RED}✗${NC} OpenTofu (tofu) not found in PATH"
    echo "Install OpenTofu: https://opentofu.org/docs/intro/install/"
    exit 1
fi
echo -e "${GREEN}✓${NC} OpenTofu found: $(tofu version | head -1)"

# Check if terraform.tfvars exists
if [ ! -f "terraform.tfvars" ]; then
    echo -e "${YELLOW}⚠${NC}  terraform.tfvars not found"
    if [ -f "terraform.tfvars.example" ]; then
        echo "  Copy terraform.tfvars.example to terraform.tfvars and configure it"
    fi
else
    echo -e "${GREEN}✓${NC} terraform.tfvars exists"
fi

# Check if we're initialized
if [ ! -d ".terraform" ]; then
    echo -e "${YELLOW}⚠${NC}  Terraform not initialized - running tofu init..."
    if tofu init; then
        echo -e "${GREEN}✓${NC} Terraform initialized successfully"
    else
        echo -e "${RED}✗${NC} Terraform initialization failed"
        exit 1
    fi
else
    echo -e "${GREEN}✓${NC} Terraform initialized"
fi

echo ""

# Load B2 configuration
if [ -f "$SERVER_DIR/.env" ]; then
    set -a; source "$SERVER_DIR/.env"; set +a
fi

# Configure rclone via env vars (no rclone.conf needed)
if [ -f "$SERVER_DIR/scripts/lib/rclone-env.sh" ]; then
    source "$SERVER_DIR/scripts/lib/rclone-env.sh"
fi

# Check B2 credentials (warn but don't fail)
B2_BACKUP_ENABLED=true
if [ -z "$B2_APPLICATION_KEY_ID" ] || [ "$B2_APPLICATION_KEY_ID" = "your_key_id_here" ]; then
    echo -e "${YELLOW}Warning:${NC} B2 credentials not configured"
    echo "State will only be backed up locally. Configure B2 in $SERVER_DIR/.env for cloud backups."
    B2_BACKUP_ENABLED=false
    echo ""
fi

# Check rclone (only required if B2 backup is enabled)
if [ "$B2_BACKUP_ENABLED" = "true" ] && ! command -v rclone &> /dev/null; then
    echo -e "${YELLOW}Warning:${NC} rclone not installed - B2 backup disabled"
    echo "Install rclone for cloud backups: https://rclone.org/install/"
    B2_BACKUP_ENABLED=false
    echo ""
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
    
    # Backup to B2 (if enabled)
    if [ "$B2_BACKUP_ENABLED" = "true" ]; then
        echo ""
        echo "======================================"
        echo "Backing up state to B2..."
        echo "======================================"
        
        TIMESTAMP=$(date +%Y%m%d_%H%M%S)
        if [ -z "$B2_BUCKET_NAME" ]; then
            echo -e "${RED}Error:${NC} B2_BUCKET_NAME not set in server/.env"
            echo -e "${YELLOW}Warning:${NC} Skipping B2 backup"
            B2_BACKUP_ENABLED=false
        else
            B2_BUCKET="$B2_BUCKET_NAME"
            
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
        fi
    else
        echo ""
        echo -e "${YELLOW}B2 backup skipped (not configured)${NC}"
    fi
    
    # Cleanup old local backups (keep last 10)
    ls -t terraform.tfstate.backup.* 2>/dev/null | tail -n +11 | xargs -r rm
    
    echo ""
    echo "======================================"
    if [ "$B2_BACKUP_ENABLED" = "true" ]; then
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
    else
        echo -e "${GREEN}Apply completed successfully!${NC}"
        echo "======================================"
        echo ""
        echo "Backup locations:"
        echo "  - Local: terraform.tfstate.backup.${TIMESTAMP}"
        echo ""
        echo "Configure B2 in server/.env for cloud state backups."
    fi
    echo ""
    
else
    echo ""
    echo -e "${RED}✗${NC} Apply failed"
    if [ -f "terraform.tfstate.backup.${TIMESTAMP}" ]; then
        echo "Local backup preserved: terraform.tfstate.backup.${TIMESTAMP}"
        echo ""
        echo "To restore previous state (if needed):"
        echo "  cp terraform.tfstate.backup.${TIMESTAMP} terraform.tfstate"
    fi
    exit 1
fi
