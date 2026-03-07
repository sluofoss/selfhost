# Getting Started

Welcome! This guide will take you from zero to a running self-hosted infrastructure in about 30 minutes.

## What You'll Get

After completing this guide, you'll have:

- **Immich** - Photo management (like Google Photos, but private)
- **SSL certificates** - Automatic HTTPS via Cloudflare Origin Certs or Let's Encrypt
- **Monitoring** - Grafana dashboards
- **Backups** - Automated to Backblaze B2
- **$0 hosting** - On Oracle Cloud Free Tier

## Prerequisites Checklist

Before starting, ensure you have:

- [ ] Oracle Cloud account (Free Tier eligible) with API key generated
- [ ] Domain name (or subdomain you control)
- [ ] Backblaze B2 account with bucket created
- [ ] SSH key pair generated
- [ ] OpenTofu installed locally
- [ ] ~30 minutes of uninterrupted time

> **Don't have these yet?** See [Prerequisites](01-prerequisites.md) for detailed setup instructions.

## Quick Start (If You're Impatient)

```bash
# 1. Provision infrastructure (creates server + runs cloud-init)
cd infra && tofu init && tofu apply

# 2. Wait ~5 min for cloud-init to finish, then SSH to server
ssh -i ~/.ssh/id_ed25519 ubuntu@<your-server-ip>

# 3. Configure environment files
cd ~/selfhost/server
cp .env.example .env
cp traefik/.env.example traefik/.env
cp immich/.env.example immich/.env
cp monitoring/.env.example monitoring/.env
# Edit all .env files with your values...

# 4. Run post-config setup (B2 mount, cron jobs, Docker image pull)
./scripts/setup/install.sh

# 5. Start
./start.sh
```

## Step-by-Step Guide

### Step 1: Infrastructure (5 min)

Deploy the Oracle Cloud infrastructure:

```bash
cd infra
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your OCI credentials and SSH key path
tofu init
./apply.sh
```

This creates:
- ARM instance (4 OCPUs, 24GB RAM) with cloud-init provisioning
- 200GB block volume (formatted and mounted at `/data`)
- VCN with firewall rules
- Reserved public IP

The `apply.sh` wrapper also backs up your Terraform state to B2 automatically.

Cloud-init will automatically:
- Install Docker, rclone, and dependencies
- Clone this repo to `/home/ubuntu/selfhost`
- Create the `/data` directory structure
- Format and mount the block volume
- Configure the UFW firewall

### Step 2: Configure Environment (5 min)

SSH into your server and set up your environment files:

```bash
ssh -i ~/.ssh/id_ed25519 ubuntu@<your-server-ip>

# Check cloud-init finished (should say "done")
cloud-init status

cd ~/selfhost/server

# Global config (B2 credentials, domain)
cp .env.example .env

# Traefik config (SSL, domain)
cp traefik/.env.example traefik/.env

# Immich config (photos, database)
cp immich/.env.example immich/.env

# Monitoring config (Grafana credentials)
cp monitoring/.env.example monitoring/.env

# Edit each file with nano/vim
nano .env
nano traefik/.env
nano immich/.env
nano monitoring/.env
```

### Step 3: Post-Config Setup (5 min)

Run the setup script to configure B2 mount, backup cron jobs, and pull Docker images:

```bash
./scripts/setup/install.sh

# Logout and back in for Docker permissions
exit
ssh -i ~/.ssh/id_ed25519 ubuntu@<your-server-ip>
```

### Step 4: Start Services (2 min)

```bash
cd ~/selfhost/server
./start.sh
```

This will:
1. Start Traefik (reverse proxy)
2. Start Immich (photos)
3. Optionally start monitoring

### Step 5: Configure DNS & SSL (10 min)

**Option A: Cloudflare (Recommended)**

1. In Cloudflare dashboard, add A records:
   ```
   photos.yourdomain.com  A  <your-server-ip>
   grafana.yourdomain.com A  <your-server-ip>
   ```

2. Set SSL/TLS mode to "Full (strict)"

3. Create Origin Certificate:
   ```bash
   ./scripts/setup/cloudflare-origin-cert.sh
   ```
   This creates a 15-year certificate and backs it up to B2.

**Option B: Other DNS Provider**

1. Add A records at your DNS provider
2. Traefik will automatically get Let's Encrypt certificates
3. Ensure port 80 is open for ACME challenge

Wait 2-5 minutes for DNS to propagate.

For detailed instructions, see [Cloudflare Origin Certificate Setup](../02-setup/cloudflare-origin-cert.md)

### Step 6: Verify

Visit:
- `https://photos.yourdomain.com` - Immich web UI
- `https://traefik.yourdomain.com` - Traefik dashboard
- `https://grafana.yourdomain.com` - Grafana (if enabled)

## Documentation Guide

Not sure where to find something? See [Documentation Structure](02-docs-structure.md) for a complete guide to what's in each folder.

## Next Steps

- Learn about [daily operations](../03-operations/daily-operations.md)
- Customize [backup settings](../03-operations/backup-restore.md)
- Understand the [architecture](../01-architecture/overview.md)

## Troubleshooting

Something not working? Check:

1. [Common Issues](../03-operations/troubleshooting.md)
2. Cloud-init logs: `sudo cat /var/log/cloud-init-output.log`
3. Docker logs: `docker compose logs`
4. System status: `docker compose ps`
