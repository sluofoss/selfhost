# B2 Bucket Structure

## Overview

This infrastructure uses a **single Backblaze B2 bucket** for all storage needs:
- Photos (Immich originals via rclone FUSE mount)
- Backups (databases, configs, certs)
- Terraform state

## Bucket Setup

1. Create a single bucket in Backblaze B2
2. Enable **encryption**
3. Set lifecycle to **Keep all versions**
4. Generate an application key scoped to this bucket

## Bucket Structure

```
<your-bucket-name>/
├── photos/                    # Immich photos storage (rclone mount target)
│   └── upload/               # Original uploaded photos
├── backups/                   # All backup types
│   ├── postgres/             # Database dumps
│   │   └── immich_20260307_020000.sql.gz
│   ├── configs/              # Configuration backups
│   │   ├── config-20260307_120000.tar.gz
│   │   └── latest/           # Latest config snapshot
│   ├── certs/                # SSL certificates
│   │   ├── origin-cert.pem
│   │   └── origin-key.pem
│   └── weekly/               # Full volume snapshots
│       └── 20260307/
│           ├── thumbnails.tar.gz
│           ├── postgres.tar.gz
│           └── volumes.tar.gz
└── terraform/                 # Terraform state backups
    ├── terraform.tfstate.latest/
    │   └── terraform.tfstate
    ├── terraform.tfstate.20260307_120000/
    │   └── terraform.tfstate
    └── ...
```

## Environment Variables

Configure in `server/.env`:

```bash
# B2 Credentials
B2_APPLICATION_KEY_ID=your_key_id_here
B2_APPLICATION_KEY=your_application_key_here

# Single bucket for everything
B2_BUCKET_NAME=your-bucket-name

# Paths within bucket (modify if needed)
B2_PHOTOS_PATH=photos
B2_BACKUPS_PATH=backups
B2_TERRAFORM_PATH=terraform
```

## Why Single Bucket?

**Benefits**:
- Simpler management
- Cost efficient (no multiple bucket minimums)
- Unified lifecycle policies
- Easier to monitor and backup

**Organization**:
- Use paths/folders to separate concerns
- Each service has its own namespace
- Easy to set different retention policies per path

## Accessing Data

### List all photos
```bash
rclone ls backblaze:${B2_BUCKET_NAME}/photos/
```

### List recent backups
```bash
rclone ls backblaze:${B2_BUCKET_NAME}/backups/postgres/ | tail -10
```

### Download specific backup
```bash
rclone copy backblaze:${B2_BUCKET_NAME}/backups/postgres/latest/ ./restore/
```

### Sync terraform state
```bash
rclone copy backblaze:${B2_BUCKET_NAME}/terraform/terraform.tfstate.latest/ ./
```

## Lifecycle Policies

Recommended lifecycle rules for the bucket:

| Path | Retention | Reason |
|------|-----------|--------|
| `photos/` | Forever | Original photos are irreplaceable |
| `backups/postgres/` | 30 days | Database dumps |
| `backups/configs/` | 7 days | Config files change frequently |
| `backups/certs/` | Forever | SSL certificates |
| `backups/weekly/` | 4 weeks | Full snapshots |
| `terraform/` | 90 days | State history |

Configure in B2 console or via B2 CLI.

## Cost Optimization

**Current cost structure**:
- Storage: $0.006/GB/month
- Download: $0.01/GB (first 1GB/day free)
- API calls: $0.004 per 10,000 (Class B)

**Typical monthly cost**:
- 1TB photos: ~$6
- 50GB backups: ~$0.30
- API calls: ~$0.10
- **Total: ~$6.40/month**

## Security

- B2 bucket encryption enabled
- Use application keys with minimal permissions (scoped to single bucket)
- Rotate keys periodically
- Never commit keys to git (`.env` files are gitignored)
- Config backups include `.env` files — this is acceptable for personal use since the B2 bucket itself is encrypted with keep-all-versions enabled
