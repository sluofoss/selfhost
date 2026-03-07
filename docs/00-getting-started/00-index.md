# Getting Started

Welcome! This guide will take you from zero to a running self-hosted infrastructure in about 40 minutes.

## What You'll Get

After completing the setup, you'll have:

- **Immich** - Photo management (like Google Photos, but private)
- **SSL certificates** - Automatic HTTPS via Cloudflare Origin Certs or Let's Encrypt
- **Monitoring** - Grafana dashboards
- **Backups** - Automated to Backblaze B2
- **$0 hosting** - On Oracle Cloud Free Tier

## Setup Guide

**Follow the [Complete Setup Guide](01-prerequisites.md)** — it walks you through every step in order:

1. Install local tools (SSH key, OpenTofu)
2. Create Backblaze B2 account and bucket
3. Create Oracle Cloud account and API key
4. Provision infrastructure with OpenTofu
5. Configure environment files on the server
6. Set up domain and DNS with Cloudflare
7. Generate SSL certificates
8. Verify everything works

## Quick Start (If You've Done This Before)

```bash
# 1. Provision infrastructure
cd infra
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your OCI credentials
tofu init && ./apply.sh

# 2. Wait ~5 min for cloud-init, then SSH in
ssh -i ~/.ssh/id_ed25519 ubuntu@<your-server-ip>

# 3. Configure all .env files
cd ~/selfhost/server
nano .env              # B2 credentials, domain
nano traefik/.env      # ACME email, dashboard password
nano immich/.env       # DB password, domain
nano monitoring/.env   # Grafana credentials

# 4. Run post-config setup
./scripts/setup/install.sh
exit  # Log out and back in for Docker permissions
ssh -i ~/.ssh/id_ed25519 ubuntu@<your-server-ip>

# 5. Start B2 mount and services
sudo systemctl start rclone-b2-mount
cd ~/selfhost/server && ./start.sh

# 6. Set up DNS (Cloudflare A records → server IP)
# 7. Run SSL cert script
./scripts/setup/cloudflare-origin-cert.sh
cd traefik && docker compose restart
```

## Documentation Guide

Not sure where to find something? See [Documentation Structure](02-docs-structure.md) for a complete guide to what's in each folder.

## Next Steps After Setup

- [Daily operations](../03-operations/daily-operations.md) — starting, stopping, updating services
- [Backup & restore](../03-operations/backup-restore.md) — how backups work, how to restore
- [Architecture overview](../01-architecture/overview.md) — understand why things are designed this way

## Troubleshooting

Something not working? Check:

1. [Common Issues](../03-operations/troubleshooting.md)
2. Cloud-init logs: `sudo cat /var/log/cloud-init-output.log`
3. Docker logs: `docker compose logs`
4. System status: `docker compose ps`
