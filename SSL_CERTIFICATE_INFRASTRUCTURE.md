# SSL/Certificate Infrastructure Analysis
## Selfhost Codebase Search Results

---

## OVERVIEW

This infrastructure uses **two certificate mechanisms** in combination:

1. **Let's Encrypt via DNS-01** (PRIMARY) - Automated via Traefik ACME + Cloudflare API.
   90-day certs, auto-renewed. Works for both proxied (orange-cloud) and direct (grey-cloud)
   domains. Requires `CF_DNS_API_TOKEN` in `traefik/.env`.
2. **Cloudflare Origin Certificate** (FALLBACK) - Stored in `traefik/certs/`, served as the
   TLS store `defaultCertificate` via `dynamic/certs.yml`. Acts as a safety net during the
   brief window between fresh-deploy and first ACME cert issuance. 15-year validity, only
   trusted by Cloudflare proxy (not by browsers connecting directly).

Traefik issues Let's Encrypt certs automatically on first deploy; the Origin cert is never
the primary cert for any live domain once DNS-01 has run successfully.

---

## 1. CERTIFICATE/SSL SCRIPTS

### A. cloudflare-origin-cert.sh
**Path**: `/home/sean/Projects/selfhost/server/scripts/setup/cloudflare-origin-cert.sh`
**Lines**: 353 lines
**Purpose**: Automated Cloudflare Origin Certificate creation, download, and Traefik configuration

#### What It Does (Sequential Steps):
1. **Prerequisites Check** (lines 26-62)
   - Validates traefik directory exists
   - Checks B2 configuration (.env file)
   - Validates rclone installation
   - Confirms B2 credentials are configured

2. **B2 Restoration Check** (lines 145-175)
   - Looks for existing certificates in B2 backup
   - If found, prompts user to restore from backup
   - Skips API calls if certificate already exists
   - Useful for disaster recovery scenarios

3. **Cloudflare API Token Setup** (lines 177-212)
   - Checks for cached token in `$SCRIPT_DIR/.cloudflare-token`
   - If missing, prompts user to enter API token
   - Saves token locally (permissions 600) for future runs
   - Instructs user on creating token with proper permissions

4. **Zone ID Lookup** (lines 223-247)
   - Prompts for domain name (e.g., example.com)
   - Makes API call to get Cloudflare Zone ID
   - Validates zone exists and API token has access

5. **Certificate Creation** (lines 249-271)
   - Makes API POST to `/origin_ca_certificates` endpoint
   - Creates 15-year validity certificate
   - Requests wildcard and apex domain hostnames
   - Extracts certificate and private key from JSON response

6. **Certificate Saving** (lines 276-294)
   - Creates `traefik/certs/` directory
   - Saves certificate to `origin-cert.pem` (chmod 644)
   - Saves private key to `origin-key.pem` (chmod 600)

7. **B2 Backup** (lines 306-320)
   - Uploads certificates to B2 bucket
   - Stores at `backups/certs/` path
   - Non-critical failure (prints warning but continues)

8. **Traefik Config Update** (lines 323-333)
   - Calls `update_traefik_config()` function (lines 68-143)
   - Updates `traefik.yml` to use Origin Certificates
   - Updates `docker-compose.yml` to mount `/certs` volume
   - Creates timestamped backup of original config

#### Environment Variables Required:
```bash
# From server/.env:
B2_APPLICATION_KEY_ID      # Backblaze app key ID
B2_APPLICATION_KEY         # Backblaze app key
B2_BUCKET_NAME            # B2 bucket for backups

# From user input during script:
DOMAIN                     # Domain name (e.g., example.com)
CF_API_TOKEN              # Cloudflare API token (saved to .cloudflare-token)
```

#### Files Created/Modified:
```
Creates:
  traefik/certs/origin-cert.pem        # 15-year validity certificate
  traefik/certs/origin-key.pem         # Private key (600 permissions)
  server/scripts/setup/.cloudflare-token  # API token cache (600 permissions)
  
Modifies:
  traefik/traefik.yml                  # Backed up as traefik.yml.backup.YYYYMMDD
                                       # Updated with static certificate config
  traefik/docker-compose.yml           # Adds volume mount for ./certs

Backups to B2:
  backblaze:${B2_BUCKET_NAME}/certs/origin-cert.pem
  backblaze:${B2_BUCKET_NAME}/certs/origin-key.pem
```

#### Dependencies:
- `rclone` - For B2 operations
- `curl` - For Cloudflare API calls
- `grep, cut, sed` - For parsing JSON responses
- `server/.env` - Must exist with B2 credentials
- `server/lib/rclone-env.sh` - Sourced for rclone environment

#### Key Functions:
```bash
update_traefik_config()  # Lines 68-143
  - Updates traefik.yml with origin cert paths
  - Updates docker-compose.yml to mount certs
  - Creates backup of original traefik.yml
```

#### Recovery/Restore:
```bash
# Script automatically restores from B2 if run again
# Manual restore:
rclone copy backblaze:${B2_BUCKET_NAME}/certs/ ./traefik/certs/
```

---

### B. install.sh
**Path**: `/home/sean/Projects/selfhost/server/scripts/setup/install.sh`
**Lines**: 332 lines
**Relevant to SSL**: Installs `ca-certificates` package (line 70)

**Certificate-related tasks**:
- Line 70: Installs `ca-certificates` for system SSL verification
- Creates Docker bridge network for services
- Configures rclone for B2 access
- Does NOT create or configure SSL certificates directly

---

## 2. TRAEFIK CONFIGURATION FILES

### A. traefik.yml
**Path**: `/home/sean/Projects/selfhost/server/traefik/traefik.yml`
**Lines**: 42 lines
**Purpose**: Static Traefik configuration (YAML format)

#### Current Configuration:
```yaml
# Lines 27-33: ACME/Let's Encrypt Configuration
certificatesResolvers:
  letsencrypt:
    acme:
      email: ${ACME_EMAIL}                    # From .env
      storage: /letsencrypt/acme.json         # Persistent storage
      dnsChallenge:                           # DNS-01 via Cloudflare API
        provider: cloudflare
        delayBeforeCheck: 10                  # Seconds to wait for DNS propagation
```

`CF_DNS_API_TOKEN` must be set in `traefik/.env`. Traefik picks it up via `env_file: .env`
and passes it to the Cloudflare DNS provider at runtime.

#### Environment Variables:
```bash
ACME_EMAIL=admin@example.com              # Email for Let's Encrypt notifications
CF_DNS_API_TOKEN=your_token_here          # Cloudflare API token (Zone/DNS/Edit)
```

#### Volumes Referenced:
```
/letsencrypt/       # ACME storage: acme.json persists certs across restarts
/certs/             # Origin cert fallback (served via dynamic/certs.yml)
/dynamic/           # Dynamic configuration files (middlewares.yml, certs.yml)
```

---

### B. docker-compose.yml
**Path**: `/home/sean/Projects/selfhost/server/traefik/docker-compose.yml`
**Lines**: 70 lines
**Purpose**: Traefik service definition

#### ACME/Certificate Configuration:
```yaml
# Lines 27-29: ACME configuration via command line arguments
command:
  - --certificatesresolvers.letsencrypt.acme.tlschallenge=true
  - --certificatesresolvers.letsencrypt.acme.email=${ACME_EMAIL}
  - --certificatesresolvers.letsencrypt.acme.storage=/letsencrypt/acme.json

# Lines 38-41: Volume mounts
volumes:
  - /var/run/docker.sock:/var/run/docker.sock:ro
  - ./letsencrypt:/letsencrypt              # ACME data (acme.json)
  - ./traefik.yml:/traefik.yml:ro           # Configuration file
  - ./dynamic:/dynamic:ro                   # Dynamic configs (middlewares)
  # NOTE: ./certs:/certs:ro already present for Origin cert fallback
```

#### ACME Challenge Type:
- **dnsChallenge**: DNS-01 via Cloudflare API
- No inbound port access required — Let's Encrypt reads a DNS TXT record
- Works for both orange-cloud (Cloudflare proxied) and grey-cloud (direct) domains
- Compatible with WB 8 Cloudflare IP restriction (no inbound dependency)

#### Environment Variables:
```bash
env_file:
  - .env                    # Sources ACME_EMAIL, DOMAIN, CF_DNS_API_TOKEN

# Inside .env:
DOMAIN=example.com
ACME_EMAIL=admin@example.com
TRAEFIK_PASSWORD='$apr1$...'
CF_DNS_API_TOKEN=your_cloudflare_api_token_here
```

#### Service Labels (Line 50-55):
```yaml
- "traefik.http.routers.traefik.tls.certresolver=letsencrypt"
# Uses letsencrypt resolver for dashboard certificate
```

---

### C. .env.example
**Path**: `/home/sean/Projects/selfhost/server/traefik/.env.example`
**Lines**: 12 lines
**Purpose**: Template for traefik environment configuration

#### Required Variables:
```bash
# Your domain (used for DNS resolution in Traefik rules)
DOMAIN=example.com

# Email for Let's Encrypt notifications and account creation
ACME_EMAIL=admin@example.com

# Cloudflare API token for DNS-01 cert challenge (Zone/DNS/Edit)
CF_DNS_API_TOKEN=your_cloudflare_api_token_here

# Traefik dashboard password (htpasswd hash format)
# Generate with: htpasswd -nb admin yourpassword
TRAEFIK_PASSWORD='$apr1$H6uskkkW$IgXLP6ewTrSuBkTrqE8wj/'
```

#### Security Notes:
- TRAEFIK_PASSWORD must be htpasswd hash (not plaintext)
- File should not be committed to git
- ACME_EMAIL used by Let's Encrypt for certificate notifications

---

### D. dynamic/middlewares.yml
**Path**: `/home/sean/Projects/selfhost/server/traefik/dynamic/middlewares.yml`
**Lines**: 29 lines
**Purpose**: Dynamic middleware configurations

#### TLS Security Configuration (Lines 19-29):
```yaml
tls:
  options:
    default:
      minVersion: VersionTLS12              # No TLS 1.0, 1.1
      cipherSuites:
        - TLS_ECDHE_RSA_WITH_AES_128_GCM_SHA256
        - TLS_ECDHE_RSA_WITH_AES_256_GCM_SHA384
        - TLS_ECDHE_RSA_WITH_CHACHA20_POLY1305
        - TLS_AES_128_GCM_SHA256
        - TLS_AES_256_GCM_SHA384
        - TLS_CHACHA20_POLY1305_SHA256
```

#### SSL/Security Headers (Lines 8-16):
```yaml
security-headers:
  headers:
    sslRedirect: true                      # Force HTTP → HTTPS
    forceSTSHeader: true                   # HSTS enabled
    stsIncludeSubdomains: true
    stsPreload: true
    stsSeconds: 31536000                   # 1 year HSTS
```

---

## 3. ENVIRONMENT VARIABLE DEFINITIONS

### A. Global Environment (server/.env)
**Path**: `/home/sean/Projects/selfhost/server/.env.example`

```bash
# DOMAIN CONFIGURATION
DOMAIN=example.com

# BACKBLAZE B2 (for certificate backups)
B2_APPLICATION_KEY_ID=your_key_id_here
B2_APPLICATION_KEY=your_application_key_here
B2_BUCKET_NAME=your-bucket-name
B2_PHOTOS_PATH=photos
B2_BACKUPS_PATH=backups
B2_TERRAFORM_PATH=terraform
```

**Used by**:
- cloudflare-origin-cert.sh (B2 backup)
- install.sh (general setup)
- Backup scripts

---

### B. Traefik Environment (server/traefik/.env)
**Path**: `/home/sean/Projects/selfhost/server/traefik/.env.example`

```bash
DOMAIN=example.com                    # DNS domain for services
ACME_EMAIL=admin@example.com         # Let's Encrypt email
TRAEFIK_PASSWORD='$apr1$...'         # Dashboard htpasswd hash
```

**Used by**:
- docker-compose.yml (ACME_EMAIL, DOMAIN)
- traefik.yml (ACME_EMAIL)
- dynamic/middlewares.yml (implicit through TRAEFIK_PASSWORD)

---

### C. Usage in Scripts

**cloudflare-origin-cert.sh** uses:
```bash
${B2_BUCKET_NAME}        # From server/.env
${ACME_EMAIL}            # For Let's Encrypt fallback config
${DOMAIN}                # From user input (not env var)
```

**docker-compose.yml** uses:
```bash
${ACME_EMAIL}            # Lines 28, 29
${DOMAIN}                # Line 51 (traefik dashboard hostname)
```

**traefik.yml** uses:
```bash
${ACME_EMAIL}            # Line 30 (Let's Encrypt resolver)
```

---

## 4. ACME (Automatic Certificate Management Environment) DOCUMENTATION

### Files Mentioning ACME:
1. `/home/sean/Projects/selfhost/docs/00-getting-started/00-index.md` - Line 43
2. `/home/sean/Projects/selfhost/docs/00-getting-started/01-prerequisites.md` - Line 278
3. `/home/sean/Projects/selfhost/docs/02-setup/dns-configuration.md` - Lines 151, 98
4. `/home/sean/Projects/selfhost/docs/03-operations/troubleshooting.md` - Line 98
5. `/home/sean/Projects/selfhost/README.md` - Line 24

### ACME Configuration Details:

#### ACME Resolver Name: `letsencrypt`
```yaml
certificatesResolvers:
  letsencrypt:
    acme:
      email: ${ACME_EMAIL}
      storage: /letsencrypt/acme.json
      dnsChallenge:
        provider: cloudflare
        delayBeforeCheck: 10
```

#### Challenge Type: DNS-01 via Cloudflare API
- **Why DNS Challenge**: Works for both orange-cloud and grey-cloud domains; no inbound port 443 required
- **How it works**: Traefik calls Cloudflare API to create a `_acme-challenge` TXT record; Let's Encrypt reads it
- **Requirement**: `CF_DNS_API_TOKEN` env var with Zone/DNS/Edit permission

#### ACME Storage:
- File: `/letsencrypt/acme.json` (inside container)
- Host Path: `./letsencrypt/acme.json` (Traefik service directory)
- Persists across container restarts
- Contains certificate account and issued certificates

#### Staging Server (for testing):
```yaml
# From troubleshooting docs, line 98:
--certificatesresolvers.letsencrypt.acme.caserver=https://acme-staging-v02.api.letsencrypt.org/directory
```

#### Rate Limits:
- Documented in troubleshooting.md lines 77-78
- Link: https://letsencrypt.org/docs/rate-limits/
- Main limit: 50 certificates per domain per week

---

## 5. LET'S ENCRYPT REFERENCES

### Documentation Files:
1. **README.md** - Line 24
   - Mentions "Automatic SSL (Cloudflare Origin Certs or Let's Encrypt)"

2. **docs/00-getting-started/00-index.md** - Line 10
   - "SSL certificates - Automatic HTTPS via Cloudflare Origin Certs or Let's Encrypt"

3. **docs/00-getting-started/01-prerequisites.md** - Line 278
   - "ACME_EMAIL=you@yourdomain.com" (for Let's Encrypt notifications)

4. **docs/02-setup/cloudflare-origin-cert.md** - Lines 12, 142
   - Mentions Let's Encrypt as alternative to Origin Certificates
   - Notes: "Let's Encrypt resolver is still configured as fallback"

5. **docs/02-setup/dns-configuration.md** - Lines 24, 68-106
   - "Alternative: Let's Encrypt (more complex)"
   - Instructions for using Let's Encrypt with generic DNS provider
   - Requires port 80 open for HTTP-01 challenge
   - Notes limitations vs. Origin Certificates

6. **docs/03-operations/troubleshooting.md** - Lines 77-99
   - Troubleshooting SSL Certificate Issues
   - References Let's Encrypt rate limits
   - Staging server configuration for testing

### Configuration in Code:

**docker-compose.yml** (Lines 27-30):
```yaml
- --certificatesresolvers.letsencrypt.acme.dnschallenge=true
- --certificatesresolvers.letsencrypt.acme.dnschallenge.provider=cloudflare
- --certificatesresolvers.letsencrypt.acme.email=${ACME_EMAIL}
- --certificatesresolvers.letsencrypt.acme.storage=/letsencrypt/acme.json
```

**traefik.yml** (Lines 27-34):
```yaml
certificatesResolvers:
  letsencrypt:
    acme:
      email: ${ACME_EMAIL}
      storage: /letsencrypt/acme.json
      dnsChallenge:
        provider: cloudflare
        delayBeforeCheck: 10
```

**Service Labels** (Line 54):
```yaml
- "traefik.http.routers.traefik.tls.certresolver=letsencrypt"
```

---

## 6. CLOUDFLARE CONFIGURATION

### Files Mentioning Cloudflare:
1. `/home/sean/Projects/selfhost/server/scripts/setup/cloudflare-origin-cert.sh`
2. `/home/sean/Projects/selfhost/docs/02-setup/cloudflare-origin-cert.md`
3. `/home/sean/Projects/selfhost/docs/02-setup/dns-configuration.md`

### Cloudflare Origin Certificates:

**Benefits** (from cloudflare-origin-cert.md):
- 15-year validity (no renewal automation needed)
- Free (included with Cloudflare)
- 2048-bit RSA encryption
- Secure end-to-end encryption through Cloudflare

**Trade-off**:
- Certificate only trusted by Cloudflare
- Users must access through Cloudflare, not directly to IP

### API Token Permissions Required:

From cloudflare-origin-cert.sh (lines 193-199):
```
✓ Zone:Read        (for listing zones)
✓ SSL:Edit         (for creating certificates)
✓ Zone Resources:  Include - Specific zone - yourdomain.com
```

### Certificate Endpoints Used:

**Zone Lookup**:
```
GET https://api.cloudflare.com/client/v4/zones?name=$DOMAIN
Authorization: Bearer $CF_API_TOKEN
```

**Certificate Creation**:
```
POST https://api.cloudflare.com/client/v4/zones/$ZONE_ID/origin_ca_certificates
Authorization: Bearer $CF_API_TOKEN
Content-Type: application/json

{
  "csr": "",
  "hostnames": ["*.$DOMAIN", "$DOMAIN"],
  "request_type": "origin-rsa",
  "requested_validity": 5475  # 15 years in days
}
```

### DNS Configuration (dns-configuration.md):

**Encryption Mode**: "Full (strict)" required
**Records**: A records pointing to OCI server IP
```
Type    Name                Value               TTL
A       photos              <your-oci-ip>       Auto
A       grafana             <your-oci-ip>       Auto
A       traefik             <your-oci-ip>       Auto
```

---

## 7. CERTIFICATE FLOW DIAGRAM

```
┌─────────────────────────────────────────────────────────────┐
│                    Certificate Setup                        │
└─────────────────────────────────────────────────────────────┘

Option 1: LET'S ENCRYPT DNS-01 (PRIMARY — automatic HTTPS)
┌─────────────────────────────────────────────────────────────┐
│ Prerequisite: CF_DNS_API_TOKEN set in traefik/.env          │
│ Run: ./scripts/setup/letsencrypt-cloudflare.sh              │
│                                                              │
│ What Traefik does automatically after restart:              │
│ 1. Reads CF_DNS_API_TOKEN + ACME_EMAIL from .env            │
│ 2. For each service router with certresolver=letsencrypt:   │
│    a. Calls Cloudflare API → creates _acme-challenge TXT    │
│    b. Let's Encrypt reads the TXT record                    │
│    c. Cert issued, TXT record deleted                       │
│ 3. Stores cert in /letsencrypt/acme.json (host-mounted)     │
│ 4. Renews automatically 30 days before 90-day expiry        │
│                                                              │
│ Works for: orange-cloud domains, grey-cloud domains,        │
│            domains behind any firewall (no inbound needed)  │
└─────────────────────────────────────────────────────────────┘

Option 2: CLOUDFLARE ORIGIN CERTIFICATE (FALLBACK default cert)
┌─────────────────────────────────────────────────────────────┐
│ User runs: ./scripts/setup/cloudflare-origin-cert.sh        │
│                                                              │
│ 1. Checks B2 for existing cert (disaster recovery)          │
│ 2. Gets Cloudflare Origin CA Key from user                  │
│ 3. Generates CSR + private key                              │
│ 4. Creates Origin Certificate (15-year validity)            │
│ 5. Saves to traefik/certs/                                  │
│    - origin-cert.pem                                        │
│    - origin-key.pem                                         │
│ 6. Backs up to B2: backups/certs/                           │
│ 7. (User manually) cd traefik && docker compose restart     │
│                                                              │
│ Served as: TLS store defaultCertificate (dynamic/certs.yml) │
│ Only trusted by: Cloudflare proxy (not direct browsers)     │
│ Used when: No ACME cert exists yet (fresh-deploy window)    │
└─────────────────────────────────────────────────────────────┘
```

---

## 8. DEPENDENCY MATRIX

### Script Dependencies:

**cloudflare-origin-cert.sh** depends on:
```
✓ server/.env              (B2 credentials)
✓ rclone                   (installed by install.sh)
✓ curl                     (standard utility)
✓ grep, sed, cut          (standard utilities)
✓ traefik/                 (must exist)
✓ traefik/traefik.yml      (gets backed up & rewritten)
✓ traefik/docker-compose.yml (gets updated)
```

**install.sh** depends on:
```
✓ Ubuntu 22.04 LTS
✓ apt package manager
✓ Docker (installs it)
✓ server/.env             (sources it)
```

**Traefik services** depend on:
```
✓ server/traefik/.env         (loads ACME_EMAIL, DOMAIN)
✓ traefik/traefik.yml         (static config)
✓ traefik/dynamic/middlewares.yml (security headers, TLS)
✓ docker-compose.yml          (service definition)
✓ ./letsencrypt/              (volume for ACME data)
✓ ./certs/                    (volume for Origin Certs, if used)
```

### Configuration File Flow:

```
server/.env
    ├─→ install.sh (B2, general setup)
    └─→ cloudflare-origin-cert.sh (B2 backup)

server/traefik/.env
    ├─→ docker-compose.yml (ACME_EMAIL, DOMAIN)
    ├─→ traefik.yml (ACME_EMAIL)
    └─→ dynamic/middlewares.yml (implicitly via DOMAIN)

Environment variables used:
    DOMAIN             → Traefik service hostnames
    ACME_EMAIL        → Let's Encrypt account
    B2_*              → Certificate backup to B2
    TRAEFIK_PASSWORD  → Dashboard authentication
```

---

## 9. SUMMARY TABLE

| Component | Location | Purpose | Depends On | Creates/Modifies |
|-----------|----------|---------|-----------|------------------|
| **cloudflare-origin-cert.sh** | `server/scripts/setup/` | Auto-create Origin Cert | B2, rclone, Cloudflare API | certs/, traefik.yml |
| **traefik.yml** | `server/traefik/` | Static Traefik config | ACME_EMAIL | ACME resolver, entry points |
| **docker-compose.yml** | `server/traefik/` | Service definition | .env, traefik.yml | ACME challenge, volumes |
| **middlewares.yml** | `server/traefik/dynamic/` | Security config | — | TLS options, HSTS |
| **traefik/.env** | `server/traefik/` | Traefik variables | User input | DOMAIN, ACME_EMAIL, password |
| **server/.env** | `server/` | Global variables | User input | B2 credentials, DOMAIN |
| **acme.json** | `server/traefik/letsencrypt/` | ACME storage | Let's Encrypt | Certificates, account data |
| **origin-cert.pem** | `server/traefik/certs/` | Origin Certificate | Cloudflare API | TLS for services |
| **origin-key.pem** | `server/traefik/certs/` | Origin Private Key | Cloudflare API | TLS for services |

---

## 10. TROUBLESHOOTING QUICK REFERENCE

### SSL Certificate Issues (from troubleshooting.md)

**Let's Encrypt rate limited**:
- Wait 1 hour and retry
- Use staging server for testing: `acme-staging-v02.api.letsencrypt.org`

**DNS not propagating**:
- Wait 5-10 minutes
- Verify with: `dig photos.yourdomain.com`

**Port 80 blocked**:
- Needed for HTTP-01 challenges (if using Let's Encrypt with non-proxied DNS)
- Not needed with Cloudflare Origin Certs (uses TLS challenge)
- Allow with: `sudo ufw allow 80/tcp`

**Cloudflare errors**:
- 521 Web Server Down → Check containers: `docker compose ps`
- 522 Connection Timeout → Check firewall, ensure ports 80/443 open
- 525 SSL Handshake Failed → Re-run origin cert script

**Origin Certificate not working**:
- Verify: `ls -la traefik/certs/`
- Check permissions: `chmod 600 traefik/certs/origin-key.pem`
- Check Traefik logs: `cd traefik && docker compose logs`

### Recovery Options

**Restore certificates from B2**:
```bash
rclone copy backblaze:${B2_BUCKET_NAME}/certs/ ./traefik/certs/
cd traefik && docker compose restart
```

**Create new Origin Certificate**:
```bash
cd server
./scripts/setup/cloudflare-origin-cert.sh
# Follows same process, restores from B2 if available
```

---

## FILE LOCATIONS SUMMARY

### Absolute Paths:
```
/home/sean/Projects/selfhost/server/scripts/setup/cloudflare-origin-cert.sh
/home/sean/Projects/selfhost/server/traefik/traefik.yml
/home/sean/Projects/selfhost/server/traefik/docker-compose.yml
/home/sean/Projects/selfhost/server/traefik/dynamic/middlewares.yml
/home/sean/Projects/selfhost/server/traefik/.env.example
/home/sean/Projects/selfhost/server/.env.example
/home/sean/Projects/selfhost/docs/02-setup/cloudflare-origin-cert.md
/home/sean/Projects/selfhost/docs/02-setup/dns-configuration.md
/home/sean/Projects/selfhost/docs/03-operations/troubleshooting.md
/home/sean/Projects/selfhost/docs/00-getting-started/01-prerequisites.md
/home/sean/Projects/selfhost/docs/00-getting-started/00-index.md
/home/sean/Projects/selfhost/README.md
```

### Runtime Paths (created during setup):
```
server/traefik/certs/origin-cert.pem              # Origin certificate
server/traefik/certs/origin-key.pem               # Private key
server/traefik/letsencrypt/acme.json              # Let's Encrypt data
server/scripts/setup/.cloudflare-token            # API token cache
server/traefik/traefik.yml.backup.YYYYMMDD       # Config backups
```

