# Enhanced Infrastructure Deployment Scripts

This directory contains enhanced deployment scripts that make infrastructure management more reliable and user-friendly.

## Scripts Overview

### `apply.sh` (Enhanced)
The main deployment script with improved error handling and B2 integration.

**Key Improvements:**
- ✅ **Graceful B2 handling**: Works without B2 credentials (warns but doesn't fail)
- ✅ **Pre-flight checks**: Validates OpenTofu installation, terraform.tfvars, and initialization
- ✅ **Auto-initialization**: Runs `tofu init` if `.terraform` directory is missing
- ✅ **Better error messages**: Clear guidance when things go wrong
- ✅ **Flexible backup**: Local backups always work, B2 is optional

**Usage:**
```bash
./apply.sh                    # Interactive mode
./apply.sh -auto-approve      # Auto-approve mode
```

### `recreate.sh` (New)
One-command instance recreation for development and testing.

**What it does:**
1. Taints the existing instance (`oci_core_instance.immich_instance`)
2. Runs `apply.sh -auto-approve` to recreate with latest cloud-init
3. Provides next-steps guidance

**Usage:**
```bash
./recreate.sh                # Auto-approve mode (recommended)
./recreate.sh --manual       # Manual approval mode
```

## Quick Development Workflow

### First-Time Setup
```bash
# 1. Copy and configure variables
cp terraform.tfvars.example terraform.tfvars
nano terraform.tfvars

# 2. Deploy infrastructure
./apply.sh
```

### Testing Cloud-Init Changes
```bash
# Edit cloud-init template
nano cloud-init.yml.tpl

# Recreate instance with new template
./recreate.sh

# Wait 2-3 minutes, then verify
ssh -i ~/.ssh/id_ed25519 ubuntu@$(tofu output -raw public_ip) 'cloud-init status'
```

### Production Deployment
```bash
# Configure B2 for state backups
nano ../server/.env  # Set B2 credentials

# Deploy with full backups
./apply.sh
```

## Error Handling

The enhanced scripts handle common issues gracefully:

- **Missing OpenTofu**: Clear installation instructions
- **No terraform.tfvars**: Suggests copying from example
- **Uninitialized Terraform**: Automatically runs `tofu init`
- **No B2 credentials**: Warns but continues with local backups
- **Apply failures**: Preserves state backups for recovery

## Benefits for Development

1. **Faster iteration**: `recreate.sh` makes testing cloud-init changes quick
2. **Fewer errors**: Pre-flight checks catch issues early
3. **No setup friction**: Scripts work immediately without full B2 configuration
4. **Better debugging**: Clear error messages and recovery instructions

## Production Features

- **State protection**: Multiple backup strategies (local + B2)
- **Version history**: Timestamped backups for rollback capability
- **Recovery instructions**: Clear guidance for disaster scenarios
- **Configuration validation**: Ensures all requirements are met