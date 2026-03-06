# Getting Started

Welcome! This guide will take you from zero to a running self-hosted infrastructure in about 30 minutes.

## What You'll Get

After completing this guide, you'll have:

- 🖼️ **Immich** - Photo management (like Google Photos, but private)
- 🔒 **SSL certificates** - Automatic HTTPS via Let's Encrypt
- 📊 **Monitoring** - Grafana dashboards
- 💾 **Backups** - Automated to Backblaze B2
- 💰 **$0 hosting** - On Oracle Cloud Free Tier

## Prerequisites Checklist

Before starting, ensure you have:

- [ ] Oracle Cloud account (Free Tier eligible)
- [ ] Domain name (or subdomain you control)
- [ ] Backblaze B2 account (free tier available)
- [ ] SSH key pair generated
- [ ] ~30 minutes of uninterrupted time

> **Don't have these yet?** See [Prerequisites](01-prerequisites.md) for detailed setup instructions.

## Quick Start (If You're Impatient)

```bash
# 1. Provision infrastructure
cd infra && tofu init && tofu apply

# 2. SSH to server
ssh ubuntu@<your-server-ip>

# 3. Clone repo and setup
git clone https://github.com/your-repo/selfhost.git
cd selfhost/server
./scripts/setup/install.sh

# 4. Configure
cp .env.example .env
cp traefik/.env.example traefik/.env
cp immich/.env.example immich/.env
# Edit all .env files...

# 5. Start
./start.sh
```

## Step-by-Step Guide

### Step 1: Infrastructure (5 min)

Deploy the Oracle Cloud infrastructure:

```bash
cd infra
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your OCI credentials
tofu init
tofu apply
```

This creates:
- ARM instance (4 OCPUs, 24GB RAM)
- 200GB block volume
- VCN with firewall rules

### Step 2: System Setup (10 min)

SSH into your new server and run the setup:

```bash
ssh ubuntu@<your-server-ip>

# Install Docker, configure firewall, etc
./scripts/setup/install.sh

# Logout and back in for Docker permissions
exit
ssh ubuntu@<your-server-ip>
```

### Step 3: Configure Environment (5 min)

Set up your environment files:

```bash
cd selfhost/server

# Global config (B2 backups)
cp .env.example .env

# Traefik config (SSL, domain)
cp traefik/.env.example traefik/.env

# Immich config (photos, database)
cp immich/.env.example immich/.env

# Edit each file with nano/vim
nano .env
nano traefik/.env
nano immich/.env
```

### Step 4: Start Services (2 min)

```bash
./start.sh
```

This will:
1. Start Traefik (reverse proxy)
2. Start Immich (photos)
3. Optionally start monitoring

### Step 5: Configure DNS (5 min)

Point your domain to the server:

```
photos.yourdomain.com  A  <your-server-ip>
grafana.yourdomain.com A  <your-server-ip>
```

Wait 2-5 minutes for DNS to propagate.

### Step 6: Verify

Visit:
- `https://photos.yourdomain.com` - Immich web UI
- `https://traefik.yourdomain.com` - Traefik dashboard
- `https://grafana.yourdomain.com` - Grafana (if enabled)

## Next Steps

- 📖 Learn about [daily operations](../03-operations/daily-operations.md)
- 🔧 Customize [backup settings](../03-operations/backup-restore.md)
- 🏗️ Understand the [architecture](../01-architecture/overview.md)

## Troubleshooting

Something not working? Check:

1. [Common Issues](../03-operations/troubleshooting.md)
2. Docker logs: `docker compose logs`
3. System status: `docker compose ps`

