# Prerequisites

## Required Accounts

### 1. Oracle Cloud Infrastructure (OCI)

**Why**: Hosts the server for free (Always Free tier)

**Setup**:
1. Sign up at [cloud.oracle.com](https://cloud.oracle.com)
2. Verify identity (credit card required, not charged)
3. Navigate to Compute → Instances
4. Generate an OCI API key (Profile → API Keys → Add API Key)
5. Save the generated key file to `~/.oci/oci_api_key.pem`
6. Note down your tenancy OCID, user OCID, fingerprint, and region

**What you get**:
- 4 OCPUs (ARM)
- 24GB RAM
- 200GB block storage
- 10TB/month outbound data

### 2. Domain Name + DNS Management

**Why**: SSL certificates require a real domain

**Recommended**: Cloudflare (free tier includes DNS + SSL)

**Setup**:
1. Transfer or register domain at [Cloudflare](https://dash.cloudflare.com)
2. Add A records pointing to your **reserved** server IP:
   - `photos.yourdomain.com → <server-ip>`
   - `grafana.yourdomain.com → <server-ip>`
3. SSL/TLS mode: Set to "Full (strict)"

**Note**: The infrastructure uses a **reserved public IP** that persists across server reboots. You only need to configure DNS once!

**Alternative**: Any DNS provider (Namecheap, etc.) + Let's Encrypt

**Why Cloudflare is recommended**:
- Free DNS with global CDN
- Built-in DDoS protection
- Origin Certificates (15-year SSL, no renewal automation needed)
- No need to manage DNS separately from OCI

**For this setup**: We use Cloudflare Origin Certificates (simpler than Let's Encrypt with Cloudflare)

### 3. Backblaze B2

**Why**: Cheap, durable storage for photos ($6/TB/month). All original photos are stored in B2 — we stay within OCI's free tier by keeping only thumbnails and caches locally.

**Setup**:
1. Sign up at [backblaze.com/b2](https://backblaze.com/b2)
2. Create a **single bucket** for all data (photos, backups, terraform state)
   - Enable **encryption**
   - Set lifecycle to **Keep all versions**
3. Generate Application Key:
   - Go to App Keys → Create Application Key
   - Name: `selfhost-server`
   - Access: Read/Write
   - Bucket: your bucket
   - Save Key ID and Application Key securely

See [B2 Bucket Structure](../02-setup/b2-bucket-structure.md) for how data is organized within the bucket.

## Required Tools

### Local Machine

```bash
# SSH client (usually pre-installed)
ssh -V

# SSH key pair (if you don't have one)
ssh-keygen -t ed25519 -C "your-email@example.com"

# OpenTofu (infrastructure provisioning)
# Install from https://opentofu.org/docs/intro/install/

# Optional:
# - Git (for cloning repo)
# - rclone (for managing B2 backups locally)
```

### Will Be Installed on Server

The cloud-init script and setup process installs:
- Docker CE
- Docker Compose plugin
- rclone (for B2)
- UFW (firewall)
- cron

## Knowledge Prerequisites

**Minimal required**:
- Basic Linux commands (cd, ls, nano/vim)
- SSH basics
- Understanding of domains/DNS

**Helpful but not required**:
- Docker familiarity
- SSL/TLS concepts
- Database basics

## Pre-Setup Checklist

- [ ] OCI account created and verified
- [ ] OCI API key generated and saved to `~/.oci/oci_api_key.pem`
- [ ] SSH key pair generated (`ssh-keygen -t ed25519`)
- [ ] Domain purchased/configured
- [ ] B2 account created
- [ ] B2 bucket created (single bucket, encryption on, keep all versions)
- [ ] B2 application key generated
- [ ] OpenTofu installed locally
- [ ] ~30 minutes uninterrupted time

## Time Estimates

| Task | Time |
|------|------|
| OCI setup + API key | 10 min |
| Domain/DNS | 5 min |
| B2 setup | 5 min |
| Infrastructure deploy | 5 min |
| Server setup | 15 min |
| **Total** | **~40 min** |
