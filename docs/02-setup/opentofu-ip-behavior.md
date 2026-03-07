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
- **Same state** → IP remains unchanged
- **Instance recreated** → IP stays the same, just re-attached
- **State deleted** → New IP created (bad!)
- **Explicit destroy** → IP deleted (avoid!)

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

## State Backup with apply.sh

The primary way to run OpenTofu is via the `infra/apply.sh` wrapper script. This script:

1. Creates a local timestamped backup of `terraform.tfstate`
2. Runs `tofu apply` with all passed arguments
3. On success, uploads state to B2 as both a timestamped version and a "latest" version
4. Cleans up old local backups (keeps last 10)

```bash
# Always use apply.sh instead of raw tofu apply
cd infra
./apply.sh

# Pass arguments through to tofu
./apply.sh -auto-approve
./apply.sh -var="ocpus=2"
```

This ensures your state file is never lost — even if your local machine dies, you can restore from B2.

**State backup location in B2**:
```
<your-bucket>/terraform/terraform.tfstate.<timestamp>/terraform.tfstate
<your-bucket>/terraform/terraform.tfstate.latest/terraform.tfstate
```

## Common Scenarios

### 1. Normal Operation (Adding/Modifying Resources)

```bash
cd infra
./apply.sh

# Result: IP stays exactly the same
```

### 2. Recreating Instance (Not the IP)

```bash
cd infra
./apply.sh

# Result: 
# - Instance is recreated with new OCID
# - Same reserved IP is detached from old instance
# - Same reserved IP is attached to new instance
# - IP address remains unchanged
```

### 3. Fresh Setup (No State File)

```bash
# First time setup or state file lost
cd infra
tofu init
./apply.sh

# Result: New reserved IP created
# You'll need to update DNS once
```

### 4. Complete Teardown and Rebuild

```bash
cd infra

# First, manually remove prevent_destroy from main.tf
./apply.sh

# Now you can destroy everything
tofu destroy

# Create new infrastructure
./apply.sh

# Result: New reserved IP created
```

## Best Practices

### 1. Always Use apply.sh

The wrapper script automatically backs up state to B2 after each successful apply. Never run raw `tofu apply` without backing up state.

### 2. Restore State from B2

If you lose your local state file:

```bash
# Restore latest state from B2
rclone copy backblaze:${B2_BUCKET_NAME}/terraform/terraform.tfstate.latest/ ./
```

### 3. Document the IP

After first creation, note the IP:

```bash
cd infra
tofu output instance_public_ip
```

## Recovery Scenarios

### Scenario 1: Lost State File, IP Still Exists

If you lose the state file but the IP still exists in OCI:

```bash
# Try restoring from B2 first
rclone copy backblaze:${B2_BUCKET_NAME}/terraform/terraform.tfstate.latest/ ./

# If B2 backup is also lost, import the existing IP into state
cd infra
tofu import oci_core_public_ip.immich_reserved_ip <ip-ocid>

# The OCID can be found in OCI Console → Networking → Public IPs
```

### Scenario 2: IP Accidentally Deleted

If the IP was deleted (rare with `prevent_destroy`):

```bash
# You'll get a new IP
cd infra
./apply.sh

# Get the new IP
tofu output instance_public_ip

# Update DNS records in Cloudflare
# Wait 2-5 minutes for propagation
```

## Summary

| Action | IP Changes? | Notes |
|--------|-------------|-------|
| `./apply.sh` (normal) | No | IP stays the same |
| Recreate instance | No | IP detached/reattached |
| Fresh setup | Yes | New IP created |
| `tofu destroy` | Blocked | `prevent_destroy` stops this |

## Quick Reference

```bash
# Check current IP (from state)
cd infra && tofu output instance_public_ip

# Safe to re-run anytime (IP won't change)
./apply.sh

# Get IP OCID (for imports/recovery)
tofu output reserved_public_ip_ocid

# If you MUST delete everything:
# 1. Remove prevent_destroy from main.tf
# 2. ./apply.sh
# 3. tofu destroy
```

The IP is designed to be **permanent** for the life of your infrastructure.
