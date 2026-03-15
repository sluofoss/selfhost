# Documentation Structure

This folder contains everything you need to understand, set up, and operate the self-hosted infrastructure.

## How to Use This Documentation

**Start here**: [00-index.md](./00-index.md) - Quick start guide

**Then explore** based on what you need:

| Folder | When to Read | What's Inside |
|--------|--------------|----------------|
| **00-getting-started** | First time setup | Prerequisites, quick start, how docs work |
| **01-architecture** | Planning/understanding | Why we made certain decisions, cost analysis |
| **02-setup** | Deploying infrastructure | OpenTofu, B2, DNS, SSL configuration |
| **03-operations** | Day-to-day use | Starting services, backups, troubleshooting |
| **04-services** | Using specific services | Service-specific features and config |
| **05-development** | Contributing/evolving | Design decisions, future plans |

## Folder-by-Folder Guide

### 00-getting-started/

**When**: You're new or need a refresher

| File | Purpose |
|------|---------|
| [00-index.md](./00-index.md) | Overview and quick start |
| [01-prerequisites.md](./01-prerequisites.md) | Complete step-by-step setup guide |

### 01-architecture/

**When**: You want to understand *why* things are designed this way

| File | Purpose |
|------|---------|
| [overview.md](../01-architecture/overview.md) | Core architecture decisions |
| [storage-strategy.md](../01-architecture/storage-strategy.md) | OCI + B2 hybrid explained |
| [immich-storage-decision.md](../01-architecture/immich-storage-decision.md) | Why Immich uses the lean rebuild-first storage model |
| [roadmap.md](../01-architecture/roadmap.md) | Future plans and phases |

### 02-setup/

**When**: Setting up infrastructure from scratch

| File | Purpose |
|------|---------|
| [dns-configuration.md](../02-setup/dns-configuration.md) | DNS setup (Cloudflare recommended) |
| [cloudflare-origin-cert.md](../02-setup/cloudflare-origin-cert.md) | SSL certificates via Cloudflare |
| [b2-bucket-structure.md](../02-setup/b2-bucket-structure.md) | Single B2 bucket organization |
| [opentofu-ip-behavior.md](../02-setup/opentofu-ip-behavior.md) | Reserved IP behavior & recovery |

### 03-operations/

**When**: Something is running and you need to operate it

| File | Purpose |
|------|---------|
| [daily-operations.md](../03-operations/daily-operations.md) | Start/stop, logs, updates |
| [backup-restore.md](../03-operations/backup-restore.md) | Backup strategy and recovery |
| [troubleshooting.md](../03-operations/troubleshooting.md) | Common issues and fixes |

### 04-services/

**When**: Using a specific service (Immich, Traefik, etc.)

| File | Purpose |
|------|---------|
| [authelia.md](../04-services/authelia.md) | Auth policy per service — why Immich bypasses Authelia, when to use bypass vs MFA |
| [devtools.md](../04-services/devtools.md) | code-server and Ollama stack overview |
| [trading.md](../04-services/trading.md) | Trading database layout, update flow, and backup/export ownership |

### 05-development/

**When**: Contributing or making architectural changes

Currently placeholder for:
- Architecture Decision Records (ADRs)
- Contributing guidelines
- Development notes

## Quick Reference

**I want to...**

| Goal | Go To |
|------|-------|
| Get started quickly | [00-index.md](./00-index.md) |
| Understand the design | [01-architecture/overview.md](../01-architecture/overview.md) |
| Set up the server | [00-index.md](./00-index.md#step-by-step-guide) |
| Start/stop services | [03-operations/daily-operations.md](../03-operations/daily-operations.md) |
| Fix something broken | [03-operations/troubleshooting.md](../03-operations/troubleshooting.md) |
| Set up backups | [03-operations/backup-restore.md](../03-operations/backup-restore.md) |
| Understand trading DB flow | [04-services/trading.md](../04-services/trading.md) |
| Add a new service (checklist) | [03-operations/troubleshooting.md#adding-a-new-service--pre-flight-checklist](../03-operations/troubleshooting.md#adding-a-new-service--pre-flight-checklist) |
| Understand auth / Authelia policy | [04-services/authelia.md](../04-services/authelia.md) |
| See what's planned | [01-architecture/roadmap.md](../01-architecture/roadmap.md) |

## Contributing to Docs

Found something wrong or want to add something?

1. Check which folder your change belongs to
2. Keep each file to a single topic
3. Cross-link to related docs instead of duplicating
4. Update this file if you add new folders

---

*Last updated: March 2026*
