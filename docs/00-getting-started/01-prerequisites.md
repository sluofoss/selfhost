# Complete Setup Guide

This guide walks you through every step from zero to a running self-hosted infrastructure. Follow it in order — each step depends on the previous one.

**Total time**: ~40 minutes

## What You'll Need

| Resource | Cost | Purpose |
|----------|------|---------|
| Oracle Cloud account | Free | Hosts the server |
| Domain name | ~$10/year | SSL and clean URLs |
| Cloudflare account | Free | DNS + SSL certificates |
| Backblaze B2 account | ~$6/TB/month | Photo storage + backups |

---

## Step 1: Local Tools (5 min)

These are installed on your local machine (laptop/desktop), not the server.

### 1a. SSH Key Pair

If you don't already have one:

```bash
ssh-keygen -t ed25519 -C "your-email@example.com"
```

Press Enter to accept the default path (`~/.ssh/id_ed25519`). Set a passphrase if you want.

Verify it exists:

```bash
ls ~/.ssh/id_ed25519.pub
```

### 1b. OpenTofu

Install OpenTofu (open-source Terraform) from [opentofu.org/docs/intro/install](https://opentofu.org/docs/intro/install/).

Verify:

```bash
tofu --version
```

### 1c. rclone (optional but recommended)

Useful for managing B2 backups from your local machine. Install from [rclone.org/install](https://rclone.org/install/).

### 1d. Clone This Repository

```bash
git clone https://github.com/sluofoss/selfhost.git
cd selfhost
```

---

## Step 2: Backblaze B2 Account + Bucket (5 min)

We set up B2 before OCI because the `apply.sh` script needs B2 credentials to back up Terraform state.

### 2a. Create Account

1. Go to [backblaze.com/b2](https://www.backblaze.com/b2/cloud-storage.html)
2. Click **Sign Up** and create an account
3. Verify your email

### 2b. Create a Bucket

1. In the B2 dashboard, go to **Buckets** → **Create a Bucket**
2. Settings:
   - **Bucket name**: Choose something unique (e.g., `yourname-selfhost`)
   - **Files in bucket are**: **Private**
   - **Default encryption**: **Enable**
   - **Object Lock**: Disabled
3. Click **Create a Bucket**
4. Go to **Lifecycle Settings** for this bucket and set to **Keep all versions**

**Write down**: Your bucket name — you'll need it in Step 5.

### 2c. Generate Application Key

1. Go to **Application Keys** → **Add a New Application Key**
2. Settings:
   - **Name**: `selfhost-server`
   - **Allow access to bucket**: Select your bucket
   - **Type of access**: **Read and Write**
   - Leave everything else default
3. Click **Create New Key**
4. **IMPORTANT**: Copy both values immediately (the key is shown only once):
   - **keyID** (e.g., `004a27...`)
   - **applicationKey** (e.g., `K004X8...`)

**Write down**: keyID and applicationKey — you'll need them in Step 5.

---

## Step 3: Oracle Cloud Account + API Key (10 min)

### 3a. Create Account

1. Go to [cloud.oracle.com](https://cloud.oracle.com)
2. Click **Sign Up** → **Oracle Cloud Free Tier**
3. Fill in your details:
   - Choose a **Home Region** (cannot be changed later — pick one close to you)
   - A credit card is required for verification but **will not be charged**
4. Complete verification

### 3b. Note Your Tenancy and User OCIDs

Once logged in:

1. Click your **Profile icon** (top right) → **Tenancy: \<your-tenancy\>**
2. Copy the **OCID** (starts with `ocid1.tenancy.oc1..`)

Then:

1. Click **Profile icon** → **My profile**
2. Copy the **OCID** (starts with `ocid1.user.oc1..`)

**Write down**: Tenancy OCID and User OCID.

### 3c. Find Your Compartment OCID

1. Go to **Identity & Security** → **Compartments**
2. If you only see the root compartment, that's fine — click on it
3. Copy the **OCID** (starts with `ocid1.compartment.oc1..` or `ocid1.tenancy.oc1..` for root)

**Write down**: Compartment OCID.

### 3d. Generate an API Key

This is how OpenTofu authenticates with OCI (separate from your SSH key).

1. Click **Profile icon** → **My profile**
2. Under **Resources**, click **API Keys**
3. Click **Add API Key**
4. Select **Generate API Key Pair**
5. Click **Download Private Key** — save it to `~/.oci/oci_api_key.pem`
6. Click **Add**
7. A **Configuration file preview** dialog appears — copy the **fingerprint** value

```bash
# Set correct permissions on the key
mkdir -p ~/.oci
chmod 600 ~/.oci/oci_api_key.pem
```

**Write down**: Fingerprint (e.g., `aa:bb:cc:dd:ee:ff:...`) and region (e.g., `us-ashburn-1`).

---

## Step 4: Provision Infrastructure (5 min)

Now you have everything needed to create the server.

### 4a. Configure Terraform Variables

```bash
cd infra
cp terraform.tfvars.example terraform.tfvars
```

Edit `terraform.tfvars` with the values you collected:

```hcl
# From Step 3b
tenancy_ocid     = "ocid1.tenancy.oc1..xxxxxxxx"
user_ocid        = "ocid1.user.oc1..xxxxxxxx"

# From Step 3d
fingerprint      = "aa:bb:cc:dd:ee:ff:00:11:22:33:44:55:66:77:88:99"
private_key_path = "~/.oci/oci_api_key.pem"

# From Step 3a (the region you chose at signup)
region           = "us-ashburn-1"

# From Step 3c
compartment_ocid = "ocid1.compartment.oc1..xxxxxxxx"

# From Step 1a (path to your SSH public key)
ssh_public_key_path = "~/.ssh/id_ed25519.pub"
```

### 4b. Configure B2 Credentials (for state backup)

The `apply.sh` wrapper backs up Terraform state to B2 after each apply. It needs the global `.env` configured first:

```bash
cd ../server
cp .env.example .env
```

Edit `server/.env` — fill in at minimum the B2 fields for now:

```bash
DOMAIN=example.com                          # Placeholder, you'll update this later
B2_APPLICATION_KEY_ID=004a27...             # From Step 2c
B2_APPLICATION_KEY=K004X8...               # From Step 2c
B2_BUCKET_NAME=yourname-selfhost           # From Step 2b
```

### 4c. Run OpenTofu

```bash
cd ../infra
tofu init
./apply.sh
```

This takes 2-5 minutes. When it finishes, it will output:

- **Your server's public IP address**
- **An SSH command** to connect
- **Next steps** to follow

**Write down**: The `instance_public_ip` — you'll need it for DNS.

> **Note**: If OCI says the ARM shape is unavailable, try a different availability domain or wait and retry. Free-tier ARM instances are in high demand.

### 4d. Wait for Cloud-Init

The server is now booting and running cloud-init, which automatically:
- Installs Docker, rclone, and system packages
- Clones this repository to `/home/ubuntu/selfhost`
- Formats and mounts the 200GB block volume at `/data`
- Creates the directory structure
- Configures the UFW firewall

**Wait ~5 minutes** before SSHing in, then verify:

```bash
ssh -i ~/.ssh/id_ed25519 ubuntu@<your-server-ip>
cloud-init status
# Should say: status: done
```

If it says `status: running`, wait a minute and check again.

---

## Step 5: Configure the Server (10 min)

You're now SSH'd into your server. The repo is already cloned at `~/selfhost`.

### 5a. Global Environment File

Cloud-init copied `.env.example` files as placeholders. Now fill in real values:

```bash
cd ~/selfhost/server
nano .env
```

Fill in all fields:

```bash
DOMAIN=yourdomain.com                      # Your actual domain
B2_APPLICATION_KEY_ID=004a27...            # From Step 2c
B2_APPLICATION_KEY=K004X8...              # From Step 2c
B2_BUCKET_NAME=yourname-selfhost          # From Step 2b
B2_PHOTOS_PATH=photos
B2_BACKUPS_PATH=backups
B2_TERRAFORM_PATH=terraform
```

### 5b. Traefik Environment File

```bash
nano traefik/.env
```

**Important variable relationships:**
- `DOMAIN` must match your DNS domain exactly (e.g., `yourdomain.com` — same as Cloudflare)
- `ACME_EMAIL` is independent — any email you own (Gmail, personal domain, etc.)

`ACME_EMAIL` is used by **Let's Encrypt** (ACME = Automatic Certificate Management Environment), an automatic SSL certificate service that runs as a fallback. Even if you plan to use Cloudflare Origin Certificates in Step 7, Traefik's configuration always has a Let's Encrypt resolver declared, so this email is required. Let's Encrypt uses it for certificate expiry notifications. **You don't need to set up Let's Encrypt** — just provide your email here and Traefik handles the rest automatically.

```bash
DOMAIN=yourdomain.com                       # Must match your DNS domain exactly
ACME_EMAIL=you@gmail.com                   # Any email you own (for cert notifications)
TRAEFIK_PASSWORD='$apr1$...'               # See below for how to generate
```

To generate the Traefik dashboard password hash:

```bash
# Install htpasswd if not present (cloud-init installs apache2-utils)
htpasswd -nb admin your-secure-password
# Copy the entire output as the TRAEFIK_PASSWORD value
```

### 5c. Immich Environment File

```bash
nano immich/.env
```

The important fields to change:

```bash
DB_PASSWORD=<generate-a-random-password>   # Use: openssl rand -base64 24
IMMICH_DOMAIN=photos.yourdomain.com
```

Leave `UPLOAD_LOCATION=/data/immich/b2-mount` as-is — this is the B2 FUSE mount.

### 5d. Monitoring Environment File

```bash
nano monitoring/.env
```

```bash
DOMAIN=yourdomain.com
GRAFANA_USER=admin
GRAFANA_PASSWORD=<a-secure-password>
```

### 5e. Run Post-Config Setup

This sets up the B2 rclone mount, backup cron jobs, and pulls Docker images:

```bash
./scripts/setup/install.sh
```

> **Note**: If you encounter permission issues, the script automatically fixes common problems like FUSE configuration and directory permissions. If B2 mount fails, check that your B2 credentials in `.env` are correct.

Then log out and back in so Docker group permissions take effect:

```bash
exit
ssh -i ~/.ssh/id_ed25519 ubuntu@<your-server-ip>
```

### 5f. Start the B2 Mount and Services

```bash
sudo systemctl start rclone-b2-mount

# Verify the mount is working
ls /data/immich/b2-mount/
# Should show an empty directory (or existing photos if restoring)

cd ~/selfhost/server
./start.sh
```

> **Troubleshooting B2 Mount**: If `rclone-b2-mount` fails to start:
> - Check logs: `journalctl -xeu rclone-b2-mount.service`
> - Verify B2 credentials in `.env` file
> - The install script should have fixed FUSE permissions automatically

Verify everything is running:

```bash
cd traefik && docker compose ps
cd ../immich && docker compose ps
```

All containers should show `Up` / `running`.

---

## Step 6: Domain and DNS (5 min)

### 6a. Add Domain to Cloudflare

If your domain isn't on Cloudflare yet:

1. Go to [dash.cloudflare.com](https://dash.cloudflare.com)
2. Click **Add a Site**
3. Enter your domain name
4. Select the **Free** plan
5. Cloudflare will show you two nameservers (e.g., `ada.ns.cloudflare.com`)
6. Go to your domain registrar and **change the nameservers** to the ones Cloudflare gave you
7. Wait for Cloudflare to confirm activation (usually 5-30 minutes, can take up to 24h)

### 6b. Create DNS Records

In Cloudflare dashboard, go to **DNS** → **Records** and add:

| Type | Name | Content | Proxy |
|------|------|---------|-------|
| A | `photos` | `<your-server-ip>` | Proxied (orange cloud) |
| A | `grafana` | `<your-server-ip>` | Proxied (orange cloud) |
| A | `traefik` | `<your-server-ip>` | Proxied (orange cloud) |

Replace `<your-server-ip>` with the IP from Step 4c.

### 6c. Configure SSL Mode

1. Go to **SSL/TLS** → **Overview**
2. Set encryption mode to **Full (strict)**

---

## Step 7: SSL Certificates (5 min)

### 7a. Create Cloudflare API Token

You need this for the automated certificate script.

1. Go to [dash.cloudflare.com/profile/api-tokens](https://dash.cloudflare.com/profile/api-tokens)
2. Click **Create Token**
3. Click **Get started** next to **Create Custom Token**
4. Configure:
   - **Token name**: `selfhost-origin-cert`
   - **Permissions**:
     - Zone → Zone → Read
     - Zone → SSL and Certificates → Edit
   - **Zone Resources**: Include → Specific zone → `yourdomain.com`
5. Click **Continue to summary** → **Create Token**
6. **Copy the token** (shown only once)

### 7b. Run the Certificate Script

On your server:

```bash
cd ~/selfhost/server
./scripts/setup/cloudflare-origin-cert.sh
```

The script will:
- Ask for your Cloudflare API token (paste it)
- Ask for your domain name
- Create a 15-year Origin Certificate
- Save it to `traefik/certs/`
- Back it up to B2
- Update Traefik configuration

### 7c. Restart Traefik

```bash
cd traefik && docker compose restart
```

---

## Step 8: Verify Everything (2 min)

### 8a. Test HTTPS

Wait 2-5 minutes for DNS to propagate, then visit:

- **Immich**: `https://photos.yourdomain.com`
- **Traefik dashboard**: `https://traefik.yourdomain.com` (use the admin credentials from Step 5b)
- **Grafana**: `https://grafana.yourdomain.com` (if you enabled monitoring)

### 8b. Create Your Immich Account

On first visit to `https://photos.yourdomain.com`, Immich will prompt you to create an admin account. This is your main account — the first user becomes admin.

### 8c. Verify Backups

```bash
# Check cron jobs are installed
crontab -l

# Check B2 mount is active
mountpoint -q /data/immich/b2-mount && echo "B2 mount OK" || echo "B2 mount FAILED"

# Run a manual backup to test
cd ~/selfhost/server
./scripts/backup/backup-postgres.sh
```

### 8d. Test DNS Resolution

From your local machine:

```bash
dig photos.yourdomain.com +short
# Should return your server IP
```

---

## What You Now Have

| Service | URL | Purpose |
|---------|-----|---------|
| Immich | `https://photos.yourdomain.com` | Photo management |
| Traefik | `https://traefik.yourdomain.com` | Reverse proxy dashboard |
| Grafana | `https://grafana.yourdomain.com` | Monitoring dashboards |

**Automated processes running**:
- Hourly config backup to B2 (on change)
- Daily database backup at 2 AM
- Weekly full backup on Sundays at 3 AM
- B2 FUSE mount for photo storage
- UFW firewall (ports 22, 80, 443 only)

---

## Quick Reference: All Credentials You Created

| Credential | Where It's Used | Where It's Stored |
|------------|-----------------|-------------------|
| SSH key pair | Server access | `~/.ssh/id_ed25519` (local) |
| OCI API key | OpenTofu → OCI | `~/.oci/oci_api_key.pem` (local) + `infra/terraform.tfvars` |
| OCI OCIDs | OpenTofu → OCI | `infra/terraform.tfvars` |
| B2 Key ID + Key | Backups, photo storage | `server/.env` |
| B2 Bucket name | All B2 operations | `server/.env` |
| Cloudflare API token | Origin cert script | `server/scripts/setup/.cloudflare-token` |
| Traefik password | Dashboard login | `server/traefik/.env` (hashed) |
| Immich DB password | Immich database | `server/immich/.env` |
| Grafana password | Grafana login | `server/monitoring/.env` |

All server-side credentials in `.env` files are backed up hourly to your encrypted B2 bucket.

---

## Next Steps

- [Daily operations](../03-operations/daily-operations.md) — starting, stopping, updating services
- [Backup & restore](../03-operations/backup-restore.md) — how backups work, how to restore
- [Troubleshooting](../03-operations/troubleshooting.md) — common issues and fixes
- [Architecture overview](../01-architecture/overview.md) — understand why things are designed this way
