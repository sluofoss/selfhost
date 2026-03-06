# Prerequisites

## Required Accounts

### 1. Oracle Cloud Infrastructure (OCI)

**Why**: Hosts the server for free (Always Free tier)

**Setup**:
1. Sign up at [cloud.oracle.com](https://cloud.oracle.com)
2. Verify identity (credit card required, not charged)
3. Navigate to Compute → Instances

**What you get**:
- 4 OCPUs (ARM)
- 24GB RAM
- 200GB block storage
- 10TB/month outbound data

### 2. Domain Name

**Why**: SSL certificates require a real domain

**Options**:
- Buy: Namecheap, Cloudflare (~$10/year)
- Free: DuckDNS, No-IP
- Use existing subdomain

**You'll need**:
- Ability to add A records
- Subdomains: `photos.yourdomain.com`, `grafana.yourdomain.com`

### 3. Backblaze B2

**Why**: Cheap, durable storage for photos ($6/TB/month)

**Setup**:
1. Sign up at [backblaze.com/b2](https://backblaze.com/b2)
2. Create bucket named `immich-photos`
3. Generate Application Key:
   - Go to App Keys → Create Application Key
   - Name: `immich-server`
   - Access: Read/Write
   - Bucket: `immich-photos`
   - Save Key ID and Application Key securely

## Required Tools

### Local Machine

```bash
# SSH client (usually pre-installed)
ssh -V

# Optional but recommended:
# - Git (for cloning repo)
# - Terraform/OpenTofu (for infrastructure)
```

### Will Be Installed on Server

The setup script installs:
- Docker CE
- Docker Compose plugin
- rclone (for B2)
- UFW (firewall)
- cron

## Knowledge Prerequisites

**Minimal required**:
- Basic Linux commands (cd, ls, nano/vim)
- SSH basics
- Understanding of domains/DNS

**Helpful but not required**:
- Docker familiarity
- SSL/TLS concepts
- Database basics

## Pre-Setup Checklist

- [ ] OCI account created and verified
- [ ] SSH key pair generated
- [ ] Domain purchased/configured
- [ ] B2 account created
- [ ] B2 bucket created
- [ ] B2 application key generated
- [ ] 30 minutes uninterrupted time

## Time Estimates

| Task | Time |
|------|------|
| OCI setup | 10 min |
| Domain/DNS | 5 min |
| B2 setup | 5 min |
| Infrastructure deploy | 5 min |
| Server setup | 15 min |
| **Total** | **~40 min** |

