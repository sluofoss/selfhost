#!/bin/bash

# Recreate Instance Script
# This script taints and recreates the instance in one command

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo "========================================"
echo "Instance Recreation (Taint + Apply)"
echo "========================================"
echo ""

# Check if we're in the infra directory
if [ ! -f "$SCRIPT_DIR/main.tf" ]; then
    echo -e "${RED}Error:${NC} This script must be run from the infra/ directory"
    echo "Current directory: $(pwd)"
    exit 1
fi

# Check if OpenTofu is available
if ! command -v tofu &> /dev/null; then
    echo -e "${RED}Error:${NC} OpenTofu (tofu) not found in PATH"
    exit 1
fi

# Step 1: Taint the instance
echo -e "${BLUE}Step 1: Tainting instance...${NC}"
if tofu taint oci_core_instance.immich_instance; then
    echo -e "${GREEN}✓${NC} Instance tainted successfully"
else
    echo -e "${RED}✗${NC} Failed to taint instance"
    echo "This might be normal if the instance doesn't exist yet"
fi

echo ""

# Step 2: Apply changes
echo -e "${BLUE}Step 2: Applying changes...${NC}"
echo ""

# Run the apply script with auto-approve
if [ "$1" = "--manual" ]; then
    # Manual approval mode
    ./apply.sh
else
    # Auto-approve mode (default)
    ./apply.sh -auto-approve
fi

echo ""
echo "========================================"
echo -e "${GREEN}Instance recreation completed!${NC}"
echo "========================================"
echo ""
echo "The instance has been recreated with the latest cloud-init configuration."
echo ""
echo "Next steps:"
echo "1. Wait ~2-3 minutes for cloud-init to complete"
echo "2. Check cloud-init status: ssh -i ~/.ssh/id_ed25519 ubuntu@\$(tofu output -raw public_ip) 'cloud-init status'"
echo "3. Verify setup: ssh -i ~/.ssh/id_ed25519 ubuntu@\$(tofu output -raw public_ip) 'docker --version'"
echo ""