# Troubleshooting Guide

## Quick Diagnostics

```bash
# Check everything is running
cd ~/selfhost/server/traefik && docker compose ps
cd ~/selfhost/server/immich && docker compose ps
cd ~/selfhost/server/devtools && docker compose ps

# Check recent errors
docker compose logs --tail 50 | grep -i error

# Check system resources
free -h && df -h

# Check cloud-init status (first boot only)
cloud-init status
sudo cat /var/log/cloud-init-output.log
```

## Common Issues

### Services Won't Start

**Symptom**: `docker compose up` fails or containers keep restarting

**Check**:
```bash
# View logs
docker compose logs

# Check disk space
df -h

# Check if .env files exist
ls -la .env traefik/.env immich/.env monitoring/.env devtools/.env
```

**Solutions**:

1. **Missing .env file**
   ```bash
   cp .env.example .env
   # Edit with your values
   ```

2. **Disk full**
   ```bash
   # Clean old backups
   find /data/backups -mtime +7 -delete
   
   # Clean Docker
   docker system prune
   ```

3. **Port already in use**
   ```bash
   # Find what's using port 80/443
   sudo netstat -tlnp | grep ':80'
   
   # Stop conflicting service
   sudo systemctl stop apache2 nginx
   ```

### SSL Certificate Issues

**Symptom**: HTTPS not working, certificate errors

**Check**:
```bash
# Check Traefik logs
cd traefik && docker compose logs

# Verify DNS resolves
dig photos.yourdomain.com

# Check Let's Encrypt rate limits
# https://letsencrypt.org/docs/rate-limits/
```

**Solutions**:

1. **DNS not propagated**
   - Wait 5-10 minutes after DNS changes
   - Use `dig` or `nslookup` to verify

2. **Port 80 blocked**
   ```bash
   sudo ufw allow 80/tcp
   sudo ufw allow 443/tcp
   ```

3. **Rate limited**
   - Wait 1 hour and try again
   - Or use staging server for testing:
     ```yaml
     # In traefik.yml
     - --certificatesresolvers.letsencrypt.acme.caserver=https://acme-staging-v02.api.letsencrypt.org/directory
     ```

### Certificate never issued for a new service

**Symptom**: New service is running, DNS resolves, but no cert in `acme.json` and the
domain gets a TLS error. Traefik logs at INFO level are silent — no ACME activity.

**Root cause**: Traefik's Docker provider silently skips containers whose Docker health
status is `unhealthy` or `starting`. If the container is unhealthy, Traefik never
registers its router and never requests a certificate. This produces no error log at
INFO level — the container is simply invisible to Traefik.

**Diagnosis**:
```bash
# Step 1: Check container health status
docker ps --format 'table {{.Names}}\t{{.Status}}'
# Look for "(unhealthy)" or "(health: starting)" next to your container

# Step 2: See why it is unhealthy
docker inspect <container_name> --format='{{json .State.Health}}' | jq .
# Check "Log" entries for exit code and output of the healthcheck command

# Step 3: Confirm Traefik sees no router for the domain
# Enable DEBUG logging temporarily (both places — see Debug Mode section)
# Look for: "Filtering unhealthy or starting container"
```

**Fix**:

The healthcheck in the compose file must check a port/service that is *actually running*
in the image. Common mistakes:
- Checking a port the image documentation mentions but that is not running (e.g. the
  image was updated and changed ports, or you assumed a GUI was present).
- Using `curl -sf` against an HTTP endpoint that returns 4xx or 5xx — the `-f` flag
  treats those as failure (exit 22), not success.

```bash
# Find what is actually listening inside the container
docker exec <container_name> ss -tlnp
# or
docker exec <container_name> netstat -tlnp

# Then update the healthcheck to check that port, e.g.:
# test: ["CMD-SHELL", "nc -z localhost <correct_port>"]
```

After fixing the healthcheck and redeploying, Traefik will receive the
`health_status: healthy` Docker event within seconds and immediately register the router
and trigger ACME certificate issuance.

**Note on DEBUG logging**: Traefik has two log level configurations that must both be
changed to see debug output:
1. `--log.level=DEBUG` in the CLI command block in `docker-compose.yml`
2. `level: DEBUG` in `traefik.yml`

Changing only one of them is not sufficient. Remember to restore both to `INFO` after
debugging.

### B2 Mount Not Working

**Symptom**: Photos not appearing, mount point empty

**Check**:
```bash
# Check if mounted
mountpoint -q /data/immich/b2-mount && echo "Mounted" || echo "Not mounted"

# Check rclone service
sudo systemctl status rclone-b2-mount

# Test rclone directly
rclone ls backblaze:${B2_BUCKET_NAME}/${B2_PHOTOS_PATH:-photos}/
```

**Solutions**:

1. **Rclone not configured**
   ```bash
   # Test connection (uses env vars, not rclone.conf)
   rclone ls backblaze:${B2_BUCKET_NAME}/
   ```

2. **Mount service not running**
   ```bash
   sudo systemctl start rclone-b2-mount
   sudo systemctl enable rclone-b2-mount
   ```

3. **FUSE not available**
   ```bash
   sudo apt install fuse
   ```

### Immich Won't Upload Photos

**Symptom**: Uploads fail or hang

**Check**:
```bash
# Check Immich logs
cd immich && docker compose logs immich-server

# Check B2 mount
df -h /data/immich/b2-mount

# Check disk space on thumbnails volume
df -h /data/immich/thumbnails
```

**Solutions**:

1. **B2 mount not available**
   - See B2 Mount section above

2. **Thumbnails volume full**
    ```bash
    # Check the main local-storage surfaces
    du -sh /data/immich/thumbnails /data/immich/postgres /data/immich/ml-cache /data/immich/rclone-cache
    
    # Reclaim rebuildable preview JPEGs first
    find /data/immich/thumbnails -type f -name '*_preview.jpeg' -delete
    ```

3. **Database issues**
   ```bash
   # Check postgres logs
   docker compose logs database
   
   # Check postgres is healthy
   docker exec immich_postgres pg_isready -U postgres
   
   # Restart database
   docker compose restart database
   ```

### Can't Access Web UI

**Symptom**: Browser can't connect to services

**Check**:
```bash
# Check if Traefik is running
cd traefik && docker compose ps

# Check if services are healthy
docker compose ps

# Test locally
curl http://localhost:8080  # Traefik dashboard
curl http://localhost:2283  # Immich
```

**Solutions**:

1. **Traefik not running**
   ```bash
   cd traefik
   docker compose up -d
   ```

2. **Firewall blocking**
   ```bash
   sudo ufw status
   sudo ufw allow 80/tcp
   sudo ufw allow 443/tcp
   ```

3. **Wrong domain configured**
   - Check `.env` files have correct DOMAIN
   - Verify DNS A records point to server IP

### Backup Failures

**Symptom**: Backups not appearing in B2

**Check**:
```bash
# Check backup logs
tail -f ~/selfhost/server/logs/postgres-backup.log

# Test rclone B2 connection
rclone ls backblaze:${B2_BUCKET_NAME}/${B2_BACKUPS_PATH:-backups}/

# Check cron jobs
crontab -l
```

**Solutions**:

1. **Cron not running**
   ```bash
   # Check cron service
   sudo systemctl status cron
   
   # Re-run install.sh to reinstall cron jobs
   ./scripts/setup/install.sh
   ```

2. **B2 credentials invalid**
   ```bash
   # Verify .env has correct B2 credentials
   cat .env | grep B2_
   
   # Test connection
   rclone ls backblaze:${B2_BUCKET_NAME}/
   ```

3. **Backup script errors**
   ```bash
   # Run manually to see errors
   ./scripts/backup/backup-postgres.sh
   ```

### Block Volume Issues

**Symptom**: `/data` directory missing or not writable

**Check**:
```bash
# Check mount
df -h /data
lsblk

# Check fstab
cat /etc/fstab | grep data
```

**Solutions**:

1. **Volume not mounted**
   ```bash
   sudo mount -a
   ```

2. **Volume not formatted** (fresh instance)
   ```bash
   # Cloud-init should handle this, but if it didn't:
   # Find the device (usually /dev/sdb)
   lsblk
   sudo mkfs.ext4 /dev/sdb
   sudo mount /dev/sdb /data
   ```

## Adding a New Service — Pre-flight Checklist

Lessons from production debugging. Run through this before declaring a new service
"deployed".

### 1. Healthcheck must match what is actually running

Before writing the healthcheck, verify the ports:

```bash
# Inspect the image metadata to see what it declares
docker image inspect <image> --format='{{json .Config.ExposedPorts}}'

# After starting the container, verify what is listening
docker exec <container> ss -tlnp
```

Do not trust documentation or assumptions about what port the GUI uses. Images evolve.
This was the root cause of the `tws.sluofoss.com` cert issue — the healthcheck checked
port 3000 (assumed KasmVNC) but the image only ran xRDP on port 3389.

Use `nc -z localhost <port>` for TCP port checks. Use `curl -f` only for HTTP endpoints
that return 2xx — `-f` treats 4xx/5xx as failure (exit 22).

### 2. Traefik will not route to an unhealthy container

Traefik's Docker provider silently skips containers that are `unhealthy` or `starting`.
No router is registered, no cert is requested, and no error is logged at INFO level.

**Whenever a domain is unreachable or has no TLS cert, check `docker ps` first.**
An `(unhealthy)` status on the target container is the most common root cause.

### 3. Cert issuance depends on the router being registered

The ACME certificate request is triggered by Traefik detecting a router with
`tls.certresolver=letsencrypt`. That only happens after the container is healthy.
The full dependency chain is:

```
container healthy → Traefik sees health_status:healthy event
                  → Docker provider registers router
                  → Traefik requests ACME DNS-01 cert via Cloudflare
                  → Cert appears in acme.json
```

If any step in this chain is missing, no error is surfaced at INFO level. Enable DEBUG
logging to trace the issue (see Debug Mode section — change both `docker-compose.yml`
and `traefik.yml`, not just one).

### 4. Decide the auth policy before deployment

Before adding Traefik labels, decide whether the service uses Authelia or bypasses it,
and why. See `docs/04-services/authelia.md` for the policy matrix and guidance on when
bypass is and is not appropriate. Adding the wrong middleware after the fact is easy to
miss in testing.

### 5. Verify end-to-end after startup

```bash
# Container is healthy
docker ps | grep <service>

# Router is registered in Traefik (wait up to 60s after healthy)
# Navigate to https://traefik.<DOMAIN> → HTTP → Routers and confirm the router appears

# Cert is issued (wait up to 2 min for DNS-01 propagation)
# Check: cat ~/selfhost/server/traefik/letsencrypt/acme.json | jq '.letsencrypt.Certificates[].domain'

# HTTPS works
curl -I https://<subdomain>.<DOMAIN>
```

## Getting Help

1. **Check logs first**: `docker compose logs`
2. **Check cloud-init logs**: `sudo cat /var/log/cloud-init-output.log`
3. **Search issues**: Check GitHub issues for similar problems
4. **System info**: Include output of `docker compose ps` and `docker compose logs` when asking for help

## Debug Mode

Enable debug logging:

```bash
# Traefik debug
cd traefik
docker compose down
# Edit docker-compose.yml, change --log.level=INFO to --log.level=DEBUG
docker compose up -d

# Immich debug
# Check Immich docs for debug environment variables
```
