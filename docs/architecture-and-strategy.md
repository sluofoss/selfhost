# Self-Hosted Infrastructure Architecture & Strategy

## Executive Summary

This document outlines the architecture and strategy for a self-hosted infrastructure designed to be:
- **Family-friendly**: Non-technical users shouldn't see complexity
- **Cost-effective**: Under $10/month for 1TB storage
- **Single-instance**: One ARM instance (24GB RAM) hosting all services
- **Backup-first**: Backblaze B2 as primary storage for photos/files
- **Scalable**: Phased approach from basic photo storage to full home cloud

## Architecture Decision: Single Instance

### Why Single Instance

**Pros:**
- Oracle Cloud Always Free tier eligible (4 OCPUs, 24GB RAM)
- Simple management - one server to maintain
- Low complexity for non-technical users
- Easy backup strategy (single point to backup)
- No distributed system complexity

**Cons:**
- Single point of failure
- No high availability
- Limited to single region
- Resource contention possible

**Mitigation:**
- Aggressive backup strategy to B2
- Can migrate to multi-instance if needed
- Monitoring and alerting

### State Management Strategy

All services categorized by their state requirements:

| Service Type | Examples | Storage Strategy |
|--------------|----------|------------------|
| **Stateful** | PostgreSQL, Redis | Block volume backup + B2 sync |
| **Semi-Stateful** | Immich thumbnails, cache | Local block volume only |
| **Stateless** | Reverse proxy, monitoring | No persistent storage |

### B2 Backup-First Approach

**Principle:** Store all irreplaceable data (photos, documents) in B2 as primary storage.

**Benefits:**
- Cost: ~$6/TB/month vs OCI storage costs
- Durability: 99.999999999% (11 nines)
- Geographic redundancy
- No egress fees from Oracle to B2

**Implementation:**
- Mount B2 buckets via rclone
- Original photos stored exclusively in B2
- Local OCI volume only for thumbnails/cache (ephemeral)

## Current Implementation (Phase 1)

### Immich Setup

**Service Architecture:**
```
Immich Server (port 8080)
├── PostgreSQL (database)
├── Redis (caching)
├── Machine Learning (image recognition)
└── Web UI
```

**Storage Layout:**
```
/data/immich/
├── thumbnails/     # Local OCI volume (fast access)
├── cache/          # Temporary files
└── b2-mount/       # B2 bucket mount (read-only)
    └── upload/     # Original photos in B2
```

### Hybrid Storage (OCI + B2)

**OCI (Local):**
- 200GB block volume for thumbnails
- Fast I/O for frequently accessed data
- Cache for ML models

**Backblaze B2 (Remote):**
- Original photos (irreplaceable)
- Documents and files
- Database backups
- Config backups

### Infrastructure (OCI)

**Compute:**
- Shape: VM.Standard.A1.Flex (ARM)
- OCPUs: 4
- Memory: 24GB
- Boot Volume: 120GB

**Storage:**
- Block Volume: 200GB (thumbnails/cache)
- Network: VCN with public subnet
- Security: Custom security list

**Cost:** $0/month (Always Free tier)

## Future Roadmap

### Phase 2: Shared Infrastructure

**Add:**
- Shared PostgreSQL instance (per-service databases)
- Shared Redis instance
- Centralized logging
- Docker Compose for orchestration

**Services:**
- Reverse proxy (Traefik)
- Database consolidation
- Basic monitoring

### Phase 3: Nextcloud

**Add:**
- Nextcloud instance
- Shared with Immich on same DB cluster
- B2 as primary storage for files
- Document collaboration

**Features:**
- File sync across devices
- Document editing
- Calendar/contacts
- Notes

### Phase 4: Additional Services

**Candidates:**
- Jellyfin (media streaming)
- Paperless-ngx (document management)
- Vaultwarden (password manager)
- Home Assistant (if hardware allows)

**Prerequisites:**
- All must support B2 storage
- Must be containerized
- Must not require persistent local state

### Phase 5: Monitoring & Automation

**Monitoring:**
- Prometheus + Grafana
- Uptime Kuma (external monitoring)
- Log aggregation (Loki)

**Automation:**
- Automated backups with verification
- Health checks and alerts
- Update automation
- Certificate renewal

## Service State Matrix

### Stateful Services

Require persistent storage and regular backups.

| Service | Data Type | Backup Frequency | Restore Priority |
|---------|-----------|------------------|------------------|
| PostgreSQL | Databases | Daily + hourly WAL | Critical |
| Nextcloud | User files | Real-time (B2) | Critical |
| Vaultwarden | Passwords | Daily | Critical |
| Paperless | Documents | Real-time (B2) | High |

### Semi-Stateful Services

Local cache/thumbnails only - can be rebuilt.

| Service | Data Type | Retention | Rebuild Time |
|---------|-----------|-----------|--------------|
| Immich | Thumbnails | 30 days | Hours |
| Redis | Cache | None | Minutes |
| Jellyfin | Metadata | 7 days | Hours |

### Stateless Services

No persistent data - easy to replace.

| Service | Data | Configuration |
|---------|------|---------------|
| Traefik | None | Config files |
| Grafana | Dashboards | Config files |
| Monitoring | Metrics | Time-limited |

## Backup Strategy

### What Gets Backed Up

**Critical (Daily):**
- PostgreSQL databases (pg_dump)
- Vaultwarden vault
- Configuration files

**High Priority (Hourly):**
- Changed configuration files
- Docker Compose files
- Environment files

**Continuous:**
- Photos in B2 (already primary storage)
- Documents in Nextcloud (B2 backend)

**Optional (Weekly):**
- Full block volume snapshots

### Backup Frequency

```
Continuous:  B2 bucket sync (real-time)
Hourly:      Config file changes (inotify + rclone sync)
Daily:       Database dumps (cron at 2 AM)
Weekly:      Full volume snapshots (optional)
Monthly:     Full system backup verification
```

### Recovery Procedures

**Scenario 1: Data Corruption**
```bash
# Restore database from last night's backup
# Takes: 5-15 minutes
# Impact: Data loss since last backup
```

**Scenario 2: Instance Failure**
```bash
# 1. Provision new OCI instance
# 2. Mount B2 bucket
# 3. Restore databases from B2
# 4. Start services
# Takes: 30-60 minutes
# Impact: None (B2 has all photos)
```

**Scenario 3: Complete Disaster**
```bash
# 1. Restore from B2 backups
# 2. Rebuild thumbnails (time varies)
# Takes: 1-4 hours
# Impact: Thumbnail rebuild time only
```

## Cost Analysis

### Oracle Free Tier Limits

| Resource | Limit | Used | Available |
|----------|-------|------|-----------|
| Compute | 4 OCPUs | 4 | 0 |
| Memory | 24GB | 24GB | 0 |
| Boot Volume | 200GB | 120GB | 80GB |
| Block Volume | 200GB | 200GB | 0 |
| Outbound Data | 10TB/month | ~100GB | 9.9TB |

### Backblaze B2 Estimates

| Usage | Storage Cost | Transaction Cost | Total |
|-------|-------------|------------------|-------|
| 500GB | $3.00 | ~$0.50 | $3.50 |
| 1TB | $6.00 | ~$1.00 | $7.00 |
| 2TB | $12.00 | ~$2.00 | $14.00 |

**Notes:**
- Storage: $0.006/GB/month
- Download: $0.01/GB
- Class B transactions: $0.004 per 10,000
- Class C transactions: $0.004 per 1,000

### Total Monthly Cost

| Scenario | OCI | B2 | Total |
|----------|-----|-------|-------|
| 500GB photos | $0 | $3.50 | **$3.50** |
| 1TB photos | $0 | $7.00 | **$7.00** |
| 2TB photos | $0 | $14.00 | **$14.00** |

## Security Considerations

### Single Instance Risks

**Risk: Container Escape**
- Mitigation: Run as non-root, seccomp profiles

**Risk: Privileged Container Compromise**
- Mitigation: Minimal privileged containers, network isolation

**Risk: Data Exposure**
- Mitigation: Encryption at rest (B2), encryption in transit (TLS)

**Risk: Supply Chain**
- Mitigation: Pin image versions, vulnerability scanning

### Mitigation Strategies

1. **Network Segmentation**
   - Docker networks isolate services
   - Only reverse proxy exposed externally
   - Internal services on private networks

2. **Secrets Management**
   - Environment files (not in git)
   - Docker secrets for sensitive data
   - Regular rotation of API keys

3. **Access Control**
   - SSH key-only authentication
   - Firewall rules (security lists)
   - Fail2ban for brute force protection

4. **Monitoring & Alerting**
   - Log aggregation
   - Anomaly detection
   - Alert on suspicious activity

## Decision Log

### Decisions Made

1. **Single Instance vs Multi-Instance**
   - Decision: Single instance
   - Date: Initial setup
   - Rationale: Cost, simplicity, family-friendly

2. **B2 as Primary Storage**
   - Decision: Mount B2 buckets for photos
   - Date: Initial setup
   - Rationale: Cost, durability, backup-first

3. **Docker Compose vs Kubernetes**
   - Decision: Docker Compose
   - Date: Initial setup
   - Rationale: Simplicity, single-node

4. **PostgreSQL per Service vs Shared**
   - Decision: Shared PostgreSQL
   - Date: Phase 2
   - Rationale: Resource efficiency

5. **Traefik vs Nginx Proxy Manager**
   - Decision: Traefik
   - Date: Phase 2
   - Rationale: Native Docker integration, Let's Encrypt

### Open Questions

1. **SSL/TLS Strategy**
   - Options: Let's Encrypt, Cloudflare, Self-signed
   - Status: Pending decision
   - Blocker: Domain setup

2. **Authentication (Authelia)**
   - Question: Need centralized auth?
   - Status: Phase 4 consideration
   - Impact: User experience

3. **Monitoring Depth**
   - Question: How much monitoring is needed?
   - Options: Basic (Uptime Kuma) vs Full (Prometheus)
   - Status: Phase 5

4. **Additional Services Priority**
   - Question: What to add after Nextcloud?
   - Candidates: Jellyfin, Paperless, Vaultwarden
   - Status: Pending usage patterns

5. **Database Backup Strategy**
   - Question: Hourly WAL or daily full backup?
   - Status: To be determined based on data criticality
   - Impact: Recovery point objective

---

*Last Updated: 2024*
*Next Review: After Phase 2 completion*
