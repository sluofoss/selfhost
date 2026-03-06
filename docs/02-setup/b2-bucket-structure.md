# B2 Bucket Structure

## Overview

This infrastructure uses a **single Backblaze B2 bucket** (`sluo-personal-b2`) for all storage needs:
- Photos (Immich)
- Backups (databases, configs, certs)
- Terraform state

## Bucket Structure

```
sluo-personal-b2/
├── photos/                    # Immich photos storage
│   ├── upload/               # Original uploaded photos
│   ├── library/              # Immich library files
│   └── thumbs/               # Thumbnail cache
├── backups/                   # All backup types
│   ├── postgres/             # Database dumps
│   │   ├── immich_20240307_020000.sql.gz
│   │   └── latest/           # Symlink to latest backup
│   ├── configs/              # Configuration backups
│   │   ├── config-20240307_120000.tar.gz
│   │   └── latest/           # Latest config snapshot
│   ├── certs/                # SSL certificates
│   │   ├── origin-cert.pem
│   │   └── origin-key.pem
│   └── weekly/               # Full volume snapshots
│       └── 20240307/
│           ├── thumbnails.tar.gz
│           └── postgres.tar.gz
└── terraform/                 # Terraform state backups
    ├── terraform.tfstate.latest
    ├── terraform.tfstate.20240307_120000
    └── terraform.tfstate.20240306_080000
```

## Environment Variables

Configure in `server/.env`:

```bash
# B2 Credentials
B2_APPLICATION_KEY_ID=your_key_id_here
B2_APPLICATION_KEY=your_application_key_here

# Single bucket for everything
B2_BUCKET_NAME=sluo-personal-b2

# Paths within bucket (modify if needed)
B2_PHOTOS_PATH=photos
B2_BACKUPS_PATH=backups
B2_TERRAFORM_PATH=terraform
```

## Why Single Bucket?

**Benefits**:
- ✅ Simpler management
- ✅ Cost efficient (no multiple bucket minimums)
- ✅ Unified lifecycle policies
- ✅ Easier to monitor and backup

**Organization**:
- Use paths/folders to separate concerns
- Each service has its own namespace
- Easy to set different retention policies per path

## Migration from Multiple Buckets

If you're migrating from separate buckets:

```bash
# Copy photos from old bucket
rclone copy backblaze:immich-photos backblaze:sluo-personal-b2/photos/

# Copy backups from old bucket
rclone copy backblaze:backups backblaze:sluo-personal-b2/backups/

# Verify
rclone ls backblaze:sluo-personal-b2

# Delete old buckets (after verification)
# rclone delete backblaze:immich-photos
# rclone delete backblaze:backups
```

## Accessing Data

### List all photos
```bash
rclone ls backblaze:sluo-personal-b2/photos/
```

### List recent backups
```bash
rclone ls backblaze:sluo-personal-b2/backups/postgres/ | tail -10
```

### Download specific backup
```bash
rclone copy backblaze:sluo-personal-b2/backups/postgres/latest/ ./restore/
```

### Sync terraform state
```bash
rclone copy backblaze:sluo-personal-b2/terraform/terraform.tfstate.latest ./terraform.tfstate
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

Configure in B2 console or via API.

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

- B2 encryption is always enabled
- Use application keys with minimal permissions
- Rotate keys periodically
- Never commit keys to git

