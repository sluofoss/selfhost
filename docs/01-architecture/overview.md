# Architecture Overview

## Core Philosophy

This infrastructure follows the **KISS** principle: Keep It Simple, Stupid.

- **Single instance** - One server, no distributed complexity
- **Service isolation** - Each service independent with own database
- **Backup-first** - All irreplaceable data in B2
- **Family-friendly** - Non-technical users never see the complexity
- **Free-tier only** - OCI compute costs $0; only pay for B2 storage

## Architecture Decisions

### Single Instance vs Multi-Instance

**Decision**: Single instance

**Rationale**:
- Oracle Always Free tier (24GB RAM, 4 OCPUs)
- Simple management - one SSH target
- Easy backups - single point to backup
- No distributed system headaches
- Low complexity for family members

**Trade-offs**:
- Single point of failure
- No high availability
- Limited to one region

**Mitigation**: Aggressive B2 backups allow rebuild in <1 hour.

### Service Isolation Strategy

Each service has its own database and Redis:

```
server/
├── traefik/           # Reverse proxy + ACME TLS
├── authelia/          # Forward-auth SSO/MFA gateway
├── immich/            # PostgreSQL + Redis (isolated)
├── monitoring/        # Prometheus + Grafana (stateless)
├── seafile/           # File sync (MariaDB)
├── devtools/          # code-server + Ollama
└── trading/           # TimescaleDB + TWS
```

**Decision**: Isolated databases per service

**Rationale**:
- Easy to add/remove services
- No shared state coupling
- Official docker-compose templates work unchanged
- Simple debugging

**Trade-offs**:
- Slightly higher resource usage
- Need to backup multiple databases

**When to refactor**: When we hit memory limits or have 5+ services.

### Storage: B2 Primary, OCI Cache

**Principle**: Original photos in B2 (cheap/durable), thumbnails and caches on OCI (fast).

```
User Upload
    │
    ├──► Original Photo ──► B2 Bucket via rclone FUSE mount
    │                         $6/TB/month
    │                         99.999999999% durability
    │
    └──► Thumbnails ─────► OCI Block Volume (200GB)
                              Fast I/O
                              Rebuildable if lost
```

This design ensures we stay within OCI's free tier by keeping only ephemeral data locally.

**Benefits**:
- Cost: ~$6/TB vs $100+/TB for OCI storage
- Durability: B2 has 11 nines durability
- Performance: Thumbnails served locally at SSD speed

## Network Architecture

```
Internet
    │
    ▼
┌──────────┐
│ Traefik  │◄── SSL termination (Let's Encrypt DNS-01 via Cloudflare)
│ (Proxy)  │
└────┬─────┘
     │
     ├──► Authelia (auth.example.com) ◄── forward-auth for admin surfaces
     │         │
     │         └── protects: traefik.*, grafana.*, vscode.*
     │
     ├──► Immich (photos.example.com)          — bypasses Authelia (own auth)
     ├──► immich-public-proxy (share.example.com) — public share links
     ├──► Grafana (grafana.example.com)         — Authelia one-factor
     ├──► Seafile (files.example.com)           — Authelia one-factor (web UI)
     ├──► code-server (vscode.example.com)      — Authelia two-factor
     └──► Traefik Dashboard (traefik.example.com) — Authelia two-factor
```

**Traefik** handles:
- SSL certificate management (Let's Encrypt DNS-01 via Cloudflare — auto-renewed)
- Reverse proxy routing
- Forwarding auth decisions to Authelia for protected services

A `busybox-monitor` container runs alongside Traefik to generate minimal activity, preventing OCI from reclaiming idle free-tier instances.

## State Management

| Service Type | Data | Backup Strategy |
|--------------|------|-----------------|
| **Stateful** | PostgreSQL databases | Daily dumps → B2 |
| **Semi-Stateful** | Thumbnails, previews, caches | Keep local for performance, but treat rebuildable derivatives selectively in backups |
| **Configuration** | .env files, compose files | Hourly sync → B2 (on change) |
| **Infrastructure** | Terraform state | Backed up to B2 via `apply.sh` |

See [Storage Strategy](storage-strategy.md) and [Immich Storage Decision](immich-storage-decision.md) for details.

## Security Model

1. **Network**: UFW firewall (ports 22, 80, 443 only)
2. **Transport**: HTTPS via Let's Encrypt DNS-01 (auto-renewed; Cloudflare API token in traefik `.env`)
3. **Authentication**: Authelia forward-auth SSO/MFA gateway
   - Traefik dashboard, code-server: two-factor (TOTP)
   - Grafana, Seafile web UI: one-factor (password)
   - Immich, immich-public-proxy, Obsidian/CouchDB: bypassed (own auth or intentionally public)
4. **Secrets**: `.env` files (gitignored, backed up to B2 encrypted bucket)
5. **Infrastructure**: Cloud-init for repeatable provisioning

## Scalability Limits

**Current limits**:
- Compute: 24GB RAM, 4 OCPUs (Oracle Free Tier max)
- Storage: 200GB local + unlimited B2
- Network: 10TB/month outbound

**When to upgrade**:
- RAM usage >90% consistently
- Adding 3+ more services
- Need high availability

See [Roadmap](roadmap.md) for expansion plans.
