# Self-Hosted Infrastructure

> Family-friendly home cloud running on Oracle Cloud Free Tier + Backblaze B2

## What This Is

A production-ready, cost-effective ($0-7/month) self-hosted infrastructure for photos, files, and home services. Designed for non-technical family members to use without seeing complexity.

## Quick Links

| I want to... | Go to |
|--------------|-------|
| **Get started immediately** | [Getting Started Guide](00-getting-started/00-index.md) |
| **Understand the architecture** | [Architecture Overview](01-architecture/overview.md) |
| **Set up DNS & SSL** | [DNS Configuration](02-setup/dns-configuration.md) |
| **Operate it daily** | [Operations Guide](03-operations/daily-operations.md) |
| **Fix a problem** | [Troubleshooting](03-operations/troubleshooting.md) |
| **Add a new service** | [Services](04-services/) |

## Project Status

**Current Phase: 1 (Immich Photo Management)**

- Traefik reverse proxy with SSL
- Immich photo server with B2 storage
- Automated backups to B2
- Monitoring with Grafana/Prometheus

**Next**: Phase 2 planning in [Roadmap](01-architecture/roadmap.md)

## One-Line Summary

```bash
# After initial setup, daily operation is just:
cd server && ./start.sh
```

## Architecture Highlights

```
┌─────────────────┐     ┌──────────────────┐     ┌─────────────────┐
│   Your Domain   │────▶│   Oracle Cloud   │────▶│  Backblaze B2   │
│  (Cloudflare)   │     │  (24GB ARM Free) │     │  ($6/TB Photos) │
└─────────────────┘     └──────────────────┘     └─────────────────┘
                              │
                              ├── Traefik (reverse proxy + SSL)
                              ├── Immich (photos)
                              └── Monitoring (Grafana)
```

## Cost

| Service | Monthly Cost |
|---------|-------------|
| Oracle OCI | **$0** (Always Free tier) |
| Backblaze B2 (1TB photos) | **~$7** |
| **Total** | **~$7/month** |

See [full cost analysis](01-architecture/storage-strategy.md#cost-analysis)

## Directory Structure

```
selfhost/
├── docs/               # You're here!
├── infra/              # OpenTofu for OCI provisioning
├── local/              # Local helper scripts
└── server/             # Docker Compose stacks
    ├── traefik/        # Reverse proxy
    ├── immich/         # Photo management
    ├── monitoring/     # Grafana + Prometheus
    └── scripts/        # Backup & setup scripts
```

## Getting Help

1. Check [Troubleshooting](03-operations/troubleshooting.md)
2. Review [Architecture Overview](01-architecture/overview.md)
3. File an issue on GitHub

---

**Last Updated**: March 2026
