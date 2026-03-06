# DNS Configuration

## Overview

DNS management for this infrastructure is handled **outside** of Oracle Cloud Infrastructure (OCI). We recommend using Cloudflare for DNS management, SSL certificates, and additional security features.

**Important**: The infrastructure provisions a **reserved public IP** that persists across:
- Server reboots
- Instance stop/start cycles  
- Infrastructure recreation (if using same OpenTofu state)

This means you only need to configure DNS once, and the IP will never change!

**Important**: The infrastructure provisions a **reserved public IP** that persists across:
- Server reboots
- Instance stop/start cycles  
- Infrastructure recreation (if using same OpenTofu state)

This means you only need to configure DNS once, and the IP will never change!

## Why Cloudflare?

**Benefits of using Cloudflare DNS**:
- ✅ **Free** - No cost for DNS management
- ✅ **Fast** - Global anycast network (faster than OCI DNS)
- ✅ **Secure** - Built-in DDoS protection
- ✅ **Simple SSL** - Origin Certificates (15-year validity, no automation needed)
- ✅ **Flexible** - Easy to change server IPs without touching OCI

**Alternative**: You can use any DNS provider (Namecheap, Route53, etc.) but you'll need to:
- Set up Let's Encrypt separately
- Manage certificate renewal
- Handle SSL configuration manually

## Cloudflare Setup

### 1. Add Domain to Cloudflare

If not already done:
1. Go to [Cloudflare Dashboard](https://dash.cloudflare.com)
2. Click "Add a Site"
3. Enter your domain
4. Follow instructions to change nameservers at your registrar

### 2. Configure DNS Records

Add A records pointing to your OCI server IP:

```
Type    Name                Value               TTL
A       photos              <your-oci-ip>       Auto
A       grafana             <your-oci-ip>       Auto
A       traefik             <your-oci-ip>       Auto
```

**Where to find your OCI IP**:
```bash
cd infra && tofu output instance_public_ip
# Or check OCI Console → Compute → Instances
```

### 3. SSL/TLS Configuration

**Recommended**: Origin Certificates (easiest)

1. Go to SSL/TLS → Overview
2. Set encryption mode to **"Full (strict)"**
3. Go to SSL/TLS → Origin Server
4. Click "Create Certificate"
5. Use our automated script:
   ```bash
   ./scripts/setup/cloudflare-origin-cert.sh
   ```

**Alternative**: Let's Encrypt (more complex)

If you prefer Let's Encrypt certificates instead of Origin Certificates:
1. Keep encryption mode as **"Full"**
2. Ensure port 80 is accessible
3. Traefik will automatically obtain certificates

### 4. Additional Cloudflare Settings (Optional)

**Caching**:
- Auto Minify: Enable for JS, CSS, HTML
- Browser Cache TTL: 4 hours

**Security**:
- Security Level: Medium
- Challenge Passage: 30 minutes

**Page Rules** (paid feature):
- Cache static assets longer
- Redirect HTTP to HTTPS

## Other DNS Providers

If you prefer not to use Cloudflare:

### Generic DNS Setup

1. Add A records at your provider:
   ```
   photos.yourdomain.com  A  <oci-ip>
   ```

2. Ensure port 80 is open for Let's Encrypt:
   ```bash
   sudo ufw allow 80/tcp
   sudo ufw allow 443/tcp
   ```

3. Traefik will automatically handle SSL certificates

### Provider-Specific Notes

**Namecheap**:
- Advanced DNS → Host Records
- TTL: Automatic (5 min for changes)

**Route53**:
- Create A records in your hosted zone
- Can use alias records for better availability

**GoDaddy**:
- DNS Management → Add records
- Note: GoDaddy free DNS is slower

## Troubleshooting DNS

### DNS Not Propagating

Check propagation:
```bash
# Check global DNS
 dig photos.yourdomain.com +short

# Check specific nameserver
dig @1.1.1.1 photos.yourdomain.com +short

# Check with nslookup
nslookup photos.yourdomain.com
```

Wait 5-10 minutes after making changes. Cloudflare usually propagates within 2 minutes.

### SSL Certificate Issues

**Origin Certificate not working**:
1. Check Cloudflare SSL/TLS mode is "Full (strict)"
2. Verify certificate files exist in `traefik/certs/`
3. Check Traefik logs: `docker compose logs`

**Let's Encrypt failing**:
1. Verify port 80 is open
2. Check firewall rules
3. Ensure DNS resolves to correct IP
4. Check Cloudflare isn't blocking ACME challenge

### Cloudflare Errors

**521 Web Server is Down**:
- Server is not responding
- Check: `docker compose ps` and `docker compose logs`

**522 Connection Timed Out**:
- Firewall blocking Cloudflare IPs
- Check: `sudo ufw status` and ensure ports 80/443 are open

**525 SSL Handshake Failed**:
- Origin certificate issue
- Re-run: `./scripts/setup/cloudflare-origin-cert.sh`

## Migration Scenarios

### Moving to New Server

If you need to migrate to a new OCI instance:

1. **Keep same domain** - Just update DNS records
2. **Restore certificates** - From B2 backup:
   ```bash
   rclone copy backblaze:${B2_BACKUP_BUCKET:-backups}/certs/ ./traefik/certs/
   ```
3. **Update DNS** - Change A records to new IP
4. **Wait 2-5 minutes** - DNS propagation

### Changing DNS Providers

If moving away from Cloudflare:
1. Export DNS records from Cloudflare
2. Import to new provider
3. Update nameservers at registrar
4. Wait 24-48 hours for full propagation
5. **Note**: You'll lose Cloudflare Origin Certificates, switch to Let's Encrypt

## Next Steps

After DNS is configured:
1. [Set up Origin Certificates](cloudflare-origin-cert.md) (if using Cloudflare)
2. [Start services](../03-operations/daily-operations.md)
3. [Verify SSL is working](../03-operations/troubleshooting.md)
