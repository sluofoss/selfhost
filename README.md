# Self-Hosted Infrastructure

> Family-friendly home cloud running on Oracle Cloud Free Tier + Backblaze B2

## 🚀 Quick Start

**New here?** → [Getting Started Guide](docs/00-getting-started/00-index.md)

```bash
# TL;DR
./scripts/setup/install.sh  # One-time setup
./start.sh                  # Start everything
```

## What Is This?

A production-ready, cost-effective (~$7/month) self-hosted infrastructure for:
- 📸 **Photos** (Immich - like Google Photos but private)
- 📊 **Monitoring** (Grafana dashboards)
- 🔒 **Automatic SSL** (Let's Encrypt)
- 💾 **Backups** (Automated to Backblaze B2)
- 💰 **$0 hosting** (Oracle Cloud Free Tier)

## 📚 Documentation

| Topic | Location |
|-------|----------|
| **Getting Started** | [00-getting-started/](docs/00-getting-started/) |
| **Architecture** | [01-architecture/](docs/01-architecture/) |
| **Setup Guide** | [02-setup/](docs/02-setup/) |
| **Daily Operations** | [03-operations/](docs/03-operations/) |
| **Service Docs** | [04-services/](docs/04-services/) |
| **Architecture Decisions** | [05-development/](docs/05-development/) |

## 🏗️ Architecture

```
Internet → Traefik (SSL) → Services (Immich, Grafana)
                ↓
         Backblaze B2 (Photos & Backups)
```

- **Single ARM instance** (24GB RAM, Oracle Free Tier)
- **Hybrid storage**: Local cache + B2 primary
- **Service isolation**: Each service independent
- **Backup-first**: Everything in B2

See [Architecture Overview](docs/01-architecture/overview.md) for details.

## 💰 Cost

| Service | Monthly Cost |
|---------|-------------|
| Oracle OCI | **$0** |
| Backblaze B2 (1TB) | **~$7** |
| **Total** | **~$7/month** |

## 📁 Project Structure

```
selfhost/
├── docs/               # 📚 Documentation
├── infra/              # Terraform for OCI
├── local/              # Local helper scripts
└── server/             # Docker Compose stacks
    ├── traefik/
    ├── immich/
    └── monitoring/
```

## 🎯 Status

**Phase 1**: ✅ Complete (Immich + Monitoring)

**Phase 2**: Planned (Nextcloud)

See [Roadmap](docs/01-architecture/roadmap.md) for full details.

## 🤝 Contributing

See [Architecture Decisions](docs/05-development/decisions.md) for design rationale.

---

**[📖 Read the Docs](docs/README.md)** | **[🚀 Get Started](docs/00-getting-started/00-index.md)**
