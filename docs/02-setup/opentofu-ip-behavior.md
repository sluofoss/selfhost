# Reserved Public IP & OpenTofu Behavior

## Does the IP Remain the Same on OpenTofu Re-run?

**Short Answer**: **Yes**, as long as you don't explicitly destroy the infrastructure.

## How It Works

### State File Tracking

OpenTofu maintains a **state file** (`terraform.tfstate`) that tracks all resources including:
- The reserved public IP (`oci_core_public_ip`)
- The instance
- All associations

When you run `tofu apply`:
- ✅ **Same state** → IP remains unchanged
- ✅ **Instance recreated** → IP stays the same, just re-attached
- ⚠️ **State deleted** → New IP created (bad!)
- ❌ **Explicit destroy** → IP deleted (avoid!)

### Protection Mechanisms

We've added `prevent_destroy = true` to the reserved IP:

```hcl
resource "oci_core_public_ip" "immich_reserved_ip" {
  # ... configuration ...
  
  lifecycle {
    prevent_destroy = true  # Prevents accidental deletion
  }
}
```

This means:
- `tofu destroy` will **fail** with an error (protects the IP)
- You must explicitly remove the `prevent_destroy` to delete the IP

## Common Scenarios

### 1. Normal Operation (Adding/Modifying Resources)

```bash
# Add a new service or modify configuration
cd infra
tofu apply

# Result: IP stays exactly the same ✅
```

### 2. Recreating Instance (Not the IP)

```bash
# Instance needs to be recreated (e.g., different image)
cd infra
tofu apply

# Result: 
# - Instance is recreated with new OCID
# - Same reserved IP is detached from old instance
# - Same reserved IP is attached to new instance
# - IP address remains unchanged ✅
```

### 3. Fresh Setup (No State File)

```bash
# First time setup or state file deleted
cd infra
tofu init
tofu apply

# Result: New reserved IP created
# You'll need to update DNS once ⚠️
```

### 4. Complete Teardown and Rebuild

```bash
# You want to start completely fresh
cd infra

# First, manually remove prevent_destroy from main.tf
tofu apply

# Now you can destroy everything
tofu destroy

# Create new infrastructure
tofu apply

# Result: New reserved IP created ⚠️
```

## Best Practices

### 1. Backup the State File

```bash
# Regular backup
cp infra/terraform.tfstate infra/terraform.tfstate.backup.$(date +%Y%m%d)

# Or use remote state (recommended for production)
# Configure S3 backend in providers.tf
```

### 2. Store State in Version Control (Carefully)

```bash
# Add to .gitignore to avoid committing sensitive state
echo "infra/terraform.tfstate*" >> .gitignore

# Or use git-crypt for encrypted state storage
git-crypt init
echo "infra/terraform.tfstate filter=git-crypt diff=git-crypt" >> .gitattributes
```

### 3. Use Remote State Backend (Production)

For production, use remote state (S3, OCI Object Storage, etc.):

```hcl
# infra/providers.tf
terraform {
  backend "s3" {
    bucket = "my-terraform-state"
    key    = "selfhost/terraform.tfstate"
    region = "us-east-1"
  }
}
```

### 4. Document the IP

After first creation, document the IP:

```bash
# Get the IP and save it
cd infra
tofu output instance_public_ip > ../RESERVED_IP.txt

# Add to version control (safe, it's just the IP)
git add ../RESERVED_IP.txt
git commit -m "Add reserved IP address"
```

## Recovery Scenarios

### Scenario 1: Lost State File, IP Still Exists

If you lose the state file but the IP still exists in OCI:

```bash
# Import the existing IP into state
cd infra
tofu import oci_core_public_ip.immich_reserved_ip <ip-ocid>

# The OCID can be found in OCI Console → Networking → Public IPs
```

### Scenario 2: IP Accidentally Deleted

If the IP was deleted (rare with `prevent_destroy`):

```bash
# You'll get a new IP
cd infra
tofu apply

# Get the new IP
tofu output instance_public_ip

# Update DNS records in Cloudflare
# Wait 2-5 minutes for propagation
```

## Summary

| Action | IP Changes? | Notes |
|--------|-------------|-------|
| `tofu apply` (normal) | ❌ No | IP stays the same |
| Recreate instance | ❌ No | IP detached/reattached |
| Fresh setup | ✅ Yes | New IP created |
| `tofu destroy` | ⚠️ Blocked | `prevent_destroy` stops this |

## Quick Reference

```bash
# Check current IP (from state)
cd infra && tofu output instance_public_ip

# Safe to re-run anytime (IP won't change)
tofu apply

# Get IP OCID (for imports/recovery)
tofu output reserved_public_ip_ocid

# If you MUST delete everything:
# 1. Remove prevent_destroy from main.tf
# 2. tofu apply
# 3. tofu destroy
```

## Recommendation

**For your use case**: The IP will remain stable across normal OpenTofu operations. Just:
1. Don't delete the `terraform.tfstate` file
2. Don't run `tofu destroy` without removing `prevent_destroy` first
3. Back up the state file periodically

The IP is designed to be **permanent** for the life of your infrastructure!
