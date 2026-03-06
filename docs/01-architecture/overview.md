# Architecture Overview

## Core Philosophy

This infrastructure follows the **KISS** principle: Keep It Simple, Stupid.

- **Single instance** - One server, no distributed complexity
- **Service isolation** - Each service independent with own database
- **Backup-first** - All irreplaceable data in B2
- **Family-friendly** - Non-technical users never see the complexity

## Architecture Decisions

### Single Instance vs Multi-Instance

**Decision**: Single instance

**Rationale**:
- ✅ Oracle Always Free tier (24GB RAM, 4 OCPUs)
- ✅ Simple management - one SSH target
- ✅ Easy backups - single point to backup
- ✅ No distributed system headaches
- ✅ Low complexity for family members

**Trade-offs**:
- ❌ Single point of failure
- ❌ No high availability
- ❌ Limited to one region

**Mitigation**: Aggressive B2 backups allow rebuild in <1 hour.

### Service Isolation Strategy

Each service has its own database and Redis:

```
server/
├── traefik/           # Reverse proxy only
├── immich/            # PostgreSQL + Redis (isolated)
├── monitoring/        # Prometheus only (stateless)
└── future-service/    # Will have own DB
```

**Decision**: Isolated databases per service

**Rationale**:
- ✅ Easy to add/remove services
- ✅ No shared state coupling
- ✅ Official docker-compose templates work unchanged
- ✅ Simple debugging

**Trade-offs**:
- ❌ Slightly higher resource usage
- ❌ Need to backup multiple databases

**When to refactor**: When we hit memory limits or have 5+ services.

### Storage: OCI + B2 Hybrid

**Principle**: Keep thumbnails local (fast), photos in B2 (cheap/durable).

```
User Upload
    │
    ├──► Original Photo ──► B2 Bucket (primary storage)
    │                         $6/TB/month
    │                         99.999999999% durability
    │
    └──► Thumbnails ─────► OCI Block Volume (200GB)
                              Fast I/O
                              Rebuildable if lost
```

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
│ Traefik  │◄── SSL termination (Let's Encrypt)
│ (Proxy)  │
└────┬─────┘
     │
     ├──► Immich (photos.yourdomain.com)
     │
     └──► Grafana (grafana.yourdomain.com)
```

**Traefik** handles:
- SSL certificate management (automatic)
- Reverse proxy routing
- Basic auth for admin interfaces
- Rate limiting (future)

## State Management

| Service Type | Data | Backup Strategy |
|--------------|------|-----------------|
| **Stateful** | PostgreSQL databases | Daily dumps → B2 |
| **Semi-Stateful** | Thumbnails, caches | Weekly snapshots |
| **Stateless** | Config files | Hourly sync → B2 |

See [Storage Strategy](storage-strategy.md) for details.

## Security Model

1. **Network**: UFW firewall (ports 22, 80, 443 only)
2. **Transport**: Automatic HTTPS via Let's Encrypt
3. **Authentication**: Service-specific (Immich auth, Grafana auth)
4. **Secrets**: `.env` files (never in git)
5. **Updates**: Watchtower (future) for automatic security updates

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

