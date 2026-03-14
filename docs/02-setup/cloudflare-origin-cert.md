# Cloudflare Origin Certificate Setup

> **Current TLS strategy**: This stack uses **Let's Encrypt DNS-01** (via Cloudflare API) as the primary certificate source. Traefik requests and renews certificates automatically on startup — no manual cert management needed. The Cloudflare Origin Certificate approach below is a secondary/legacy option for cases where ACME is unavailable or you want a static long-lived cert alongside the Cloudflare proxy.

This guide walks you through setting up Cloudflare Origin Certificates for SSL termination.

## Why Origin Certificates?

**Benefits**:
- **15-year validity** - No renewal automation needed
- **Free** - Included with Cloudflare
- **Secure** - 2048-bit RSA encryption
- **Works through Cloudflare** - End-to-end encryption

**Trade-off**: Certificate is only trusted by Cloudflare (users must access through Cloudflare, not directly to IP).

## Prerequisites

Before starting:
1. Domain added to Cloudflare
2. DNS records pointing to your OCI server IP
3. Cloudflare API token with permissions:
   - Zone:Read
   - SSL:Edit

## Automated Setup

We provide a script that automates the entire process:

```bash
# From server directory
cd /path/to/selfhost/server

# Run the setup script
./scripts/setup/cloudflare-origin-cert.sh
```

### What the Script Does

1. **Checks B2 backup** - If certificate exists from previous setup, restores it
2. **Creates certificate** - Uses Cloudflare API to generate 15-year Origin Certificate
3. **Downloads** - Gets certificate + private key
4. **Saves locally** - Places in `traefik/certs/`
5. **Backs up to B2** - Stores copy for disaster recovery
6. **Updates Traefik** - Configures Traefik to use Origin Certificate
7. **Restarts Traefik** - Applies new configuration

### Manual Steps (If Script Fails)

#### Step 1: Create Cloudflare API Token

1. Go to https://dash.cloudflare.com/profile/api-tokens
2. Click "Create Token"
3. Use "Custom token" with these permissions:
   - **Zone:Read** - For listing zones
   - **SSL:Edit** - For creating certificates
4. Zone Resources: Include - Specific zone - yourdomain.com
5. Copy the token (shown only once)

#### Step 2: Create Origin Certificate

1. Go to your domain in Cloudflare dashboard
2. SSL/TLS → Origin Server
3. Click "Create Certificate"
4. Choose:
   - Private key type: RSA (2048)
   - Hostnames: `*.yourdomain.com, yourdomain.com`
   - Certificate validity: 15 years
5. Click "Create"
6. Copy the **Origin Certificate** and **Private key**

#### Step 3: Save Certificate

```bash
# Create certs directory
mkdir -p traefik/certs

# Save certificate
cat > traefik/certs/origin-cert.pem << 'CERT'
-----BEGIN CERTIFICATE-----
(paste your certificate here)
-----END CERTIFICATE-----
CERT

# Save private key (keep secure!)
cat > traefik/certs/origin-key.pem << 'KEY'
-----BEGIN PRIVATE KEY-----
(paste your private key here)
-----END PRIVATE KEY-----
KEY

# Set permissions
chmod 600 traefik/certs/origin-key.pem
chmod 644 traefik/certs/origin-cert.pem
```

#### Step 4: Backup to B2

```bash
# Backup certificates (uses B2_BUCKET_NAME from server/.env)
rclone copy traefik/certs/ backblaze:${B2_BUCKET_NAME}/certs/
```

#### Step 5: Update Traefik

Edit `traefik/traefik.yml`:

```yaml
entryPoints:
  websecure:
    address: ":443"
    http:
      tls:
        certificates:
          - certFile: /certs/origin-cert.pem
            keyFile: /certs/origin-key.pem
```

Update `traefik/docker-compose.yml` to mount certs:

```yaml
volumes:
  - ./certs:/certs:ro
```

#### Step 6: Restart Traefik

```bash
cd traefik
docker compose restart
```

## Verification

Test the certificate:

```bash
# Test HTTPS
curl -I https://photos.yourdomain.com

# Check certificate details
echo | openssl s_client -servername photos.yourdomain.com -connect photos.yourdomain.com:443 2>/dev/null | openssl x509 -noout -dates -subject

# Should show:
# notBefore=... (15 years from now)
# notAfter=... (15 years later)
# subject=CN = Cloudflare Origin Certificate
```

## Disaster Recovery

**If server is recreated**:

```bash
# Restore from B2 backup
rclone copy backblaze:${B2_BUCKET_NAME}/certs/ ./traefik/certs/

# Restart Traefik
cd traefik && docker compose restart
```

Or just run the setup script again - it will automatically restore from B2!

## Troubleshooting

### Certificate Not Working

1. Check Traefik logs:
   ```bash
   cd traefik && docker compose logs
   ```

2. Verify certificate files exist:
   ```bash
   ls -la traefik/certs/
   ```

3. Check file permissions:
   ```bash
   chmod 600 traefik/certs/origin-key.pem
   chmod 644 traefik/certs/origin-cert.pem
   ```

### B2 Backup Failed

1. Check rclone config:
   ```bash
   rclone config show
   ```

2. Test B2 connection:
   ```bash
   rclone ls backblaze:${B2_BUCKET_NAME}/
   ```

### API Token Issues

1. Verify token permissions in Cloudflare dashboard
2. Check token hasn't expired
3. Ensure token has access to the correct zone

## Next Steps

After setting up Origin Certificates:

1. [Configure DNS](dns-configuration.md) (if not done)
2. [Start services](../03-operations/daily-operations.md)
3. [Set up backups](../03-operations/backup-restore.md)
