# Roadmap

## Current Status: Phase 1 ✅

**Completed**:
- ✅ Oracle Cloud infrastructure (Terraform)
- ✅ Traefik reverse proxy with SSL
- ✅ Immich photo management
- ✅ Backblaze B2 storage integration
- ✅ Automated backups (daily DB, hourly configs)
- ✅ Basic monitoring (Grafana + Prometheus)

## Phase 2: Shared Infrastructure (Planned)

**Goal**: Improve resource efficiency and add core infrastructure

**Planned**:
- [ ] Shared PostgreSQL instance (reduce memory usage)
- [ ] Shared Redis instance
- [ ] Centralized logging (Loki)
- [ ] Automated security updates (Watchtower)

**Trigger**: When we add 2+ more services

## Phase 3: Nextcloud (Planned)

**Goal**: Add file sync and collaboration

**Planned**:
- [ ] Nextcloud instance
- [ ] B2 as primary storage for files
- [ ] Calendar/Contacts sync
- [ ] Document collaboration (OnlyOffice/Collabora)

**Prerequisites**: Phase 2 (shared database)

## Phase 4: Additional Services (Future)

**Candidates** (in priority order):

1. **Vaultwarden** - Password manager
   - Family password sharing
   - Easy to deploy, low resource usage

2. **Paperless-ngx** - Document management
   - OCR for scanned documents
   - B2 storage for documents

3. **Jellyfin** - Media streaming
   - Stream B2-stored media
   - Requires transcoding (resource intensive)

4. **Home Assistant** - Home automation
   - Only if hardware allows
   - May need dedicated hardware

## Phase 5: Enterprise Features (Future)

**Monitoring & Automation**:
- [ ] Uptime Kuma (external monitoring)
- [ ] Alertmanager for Prometheus alerts
- [ ] Automated backup verification
- [ ] Disaster recovery runbooks

**Security**:
- [ ] Authelia for centralized authentication
- [ ] Fail2ban for brute force protection
- [ ] Regular security audits

**Scaling** (if needed):
- [ ] Multi-instance setup
- [ ] Kubernetes migration
- [ ] CDN integration (Cloudflare)

## Decision Log

### Decisions Made

| Date | Decision | Rationale |
|------|----------|-----------|
| 2024-01 | Single instance | Cost, simplicity |
| 2024-01 | Isolated databases | Easy to maintain, official templates |
| 2024-01 | Traefik over NPM | Native Docker integration |
| 2024-01 | B2 primary storage | Cost, durability |

### Open Questions

1. **When to implement Phase 2?**
   - Current RAM usage: ~60%
   - Add 2 more services, then evaluate

2. **Which Phase 4 service first?**
   - Likely Vaultwarden (low resource, high value)
   - Family input needed

3. **Monitoring depth?**
   - Current: Basic Prometheus/Grafana
   - Need: External monitoring (Uptime Kuma)

