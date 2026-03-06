# Self-Hosted Infrastructure

This directory contains all the scripts and configuration for the self-hosted infrastructure as defined in `docs/architecture-and-strategy.md`.

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────┐
│                    Oracle Cloud (OCI)                        │
│                                                              │
│  ┌─────────────────────────────────────────────────────────┐│
│  │           VM.Standard.A1.Flex (ARM)                      ││
│  │           4 OCPUs | 24GB RAM                             ││
│  │                                                         ││
│  │  ┌─────────────────────────────────────────────────┐   ││
│  │  │        Docker Compose Stack                      │   ││
│  │  │                                                  │   ││
│  │  │  ┌─────────┐  ┌──────────┐  ┌──────────────┐  │   ││
│  │  │  │ Traefik │  │  Immich  │  │  Prometheus  │  │   ││
│  │  │  │(Proxy)  │  │ (Photos) │  │ (Monitoring) │  │   ││
│  │  │  └────┬────┘  └────┬─────┘  └──────────────┘  │   ││
│  │  │       │            │                           │   ││
│  │  │  ┌────┴────────────┴──────────┐  ┌──────────┐ │   ││
│  │  │  │  Shared Services           │  │  Grafana │ │   ││
│  │  │  │  PostgreSQL | Redis        │  │          │ │   ││
│  │  │  └────────────────────────────┘  └──────────┘ │   ││
│  │  └───────────────────────────────────────────────┘   ││
│  │                                                         ││
│  │  ┌────────────────────────────────────────────────┐   ││
│  │  │ B2 Mount (rclone)                              │   ││
│  │  │ /data/immich/b2-mount ◄── Backblaze B2         │   ││
│  │  └────────────────────────────────────────────────┘   ││
│  │                                                         ││
│  │  ┌────────────────────────────────────────────────┐   ││
│  │  │ Block Volume (200GB)                           │   ││
│  │  │ Thumbnails | Cache | Backups                   │   ││
│  │  └────────────────────────────────────────────────┘   ││
│  └─────────────────────────────────────────────────────────┘│
└─────────────────────────────────────────────────────────────┘
```

## Directory Structure

```
server/
├── docker-compose.yml          # Main service orchestration
├── .env                        # Environment variables (create from .env.example)
├── .env.example               # Example environment file
├── traefik/                   # Reverse proxy configuration
│   └── traefik-dynamic.yml
├── scripts/
│   ├── setup/
│   │   ├── install.sh        # Full system setup
│   │   └── start.sh          # Quick start services
│   └── backup/
│       ├── backup-postgres.sh    # Daily database backups
│       ├── backup-configs.sh     # Hourly config backups
│       ├── backup-weekly.sh      # Weekly full backups
│       └── restore-postgres.sh   # Database restore tool
└── monitoring/
    ├── prometheus.yml              # Prometheus configuration
    └── grafana/
        └── provisioning/           # Grafana datasources & dashboards
```

## Quick Start

### 1. Initial Setup

```bash
# SSH into your Oracle instance
ssh ubuntu@<your-instance-ip>

# Clone the repository
git clone https://github.com/your-repo/selfhost.git
cd selfhost/server

# Copy and configure environment file
cp .env.example .env
nano .env  # Edit with your values

# Run the installation script
./scripts/setup/install.sh

# Logout and login again (for Docker permissions)
exit
ssh ubuntu@<your-instance-ip>
```

### 2. Configure Backblaze B2 (Optional but Recommended)

1. Create a Backblaze B2 account at https://www.backblaze.com/b2/
2. Create a bucket named `immich-photos`
3. Generate Application Keys in the B2 console
4. Add the credentials to your `.env` file

### 3. Start Services

```bash
# Quick start
./scripts/setup/start.sh

# Or manually
docker compose up -d
```

### 4. Configure DNS

Point your domain/subdomains to your Oracle instance IP:

```
photos.example.com  A  <your-instance-ip>
grafana.example.com A  <your-instance-ip>
```

### 5. Access Services

| Service | URL | Description |
|---------|-----|-------------|
| Traefik | `http://<ip>:8080` | Reverse proxy dashboard |
| Immich | `https://photos.<domain>` | Photo management |
| Grafana | `https://grafana.<domain>` | Monitoring dashboards |

## Environment Variables

Required variables in `.env`:

```bash
# Domain & SSL
DOMAIN=example.com
ACME_EMAIL=admin@example.com
TRAEFIK_PASSWORD=...  # htpasswd encoded

# Database
POSTGRES_USER=postgres
POSTGRES_PASSWORD=secure_password

# Grafana
GRAFANA_USER=admin
GRAFANA_PASSWORD=secure_password

# Backblaze B2
B2_APPLICATION_KEY_ID=your_key_id
B2_APPLICATION_KEY=your_key
```

## Backup Strategy

Automatic backups run via cron:

| Backup Type | Frequency | Destination | Retention |
|-------------|-----------|-------------|-----------|
| Database | Daily 2 AM | Local + B2 | 7 days local, 30 days B2 |
| Configs | Hourly | B2 | 24 hours |
| Full Volume | Weekly (Sunday 3 AM) | B2 | 4 weeks |

### Manual Backup Operations

```bash
# Database backup
./scripts/backup/backup-postgres.sh

# Config backup
./scripts/backup/backup-configs.sh

# Weekly backup
./scripts/backup/backup-weekly.sh

# Restore database
./scripts/backup/restore-postgres.sh immich [backup-file]
```

## Service Management

```bash
# View all services
docker compose ps

# View logs
docker compose logs -f [service-name]

# Restart a service
docker compose restart [service-name]

# Update services
docker compose pull
docker compose up -d

# Stop all services
docker compose down

# Stop and remove volumes (WARNING: data loss)
docker compose down -v
```

## Monitoring

### Prometheus
- Scrapes metrics from all services
- Retention: 15 days
- Accessible internally only

### Grafana
- Visual dashboards for metrics
- Pre-configured with Prometheus datasource
- Access at `https://grafana.<domain>`

### Node Exporter
- System-level metrics (CPU, memory, disk)

### cAdvisor
- Container metrics and resource usage

## Troubleshooting

### B2 Mount Issues

```bash
# Check mount status
mountpoint -q /data/immich/b2-mount && echo "Mounted" || echo "Not mounted"

# Check rclone service
sudo systemctl status rclone-b2-mount

# Restart rclone mount
sudo systemctl restart rclone-b2-mount

# View rclone logs
sudo journalctl -u rclone-b2-mount -f
```

### Docker Issues

```bash
# Check Docker status
sudo systemctl status docker

# View container logs
docker logs [container-name]

# Restart Docker
sudo systemctl restart docker
```

### SSL Certificate Issues

```bash
# Force certificate renewal
docker compose exec traefik traefik --configFile=/traefik.yml

# Check certificate status
ls -la ./traefik/certs/
```

## Security Considerations

1. **Firewall**: UFW enabled with only ports 22, 80, 443 open
2. **SSL**: Automatic Let's Encrypt certificates
3. **Authentication**: Basic auth for Traefik dashboard
4. **Secrets**: Stored in `.env` file (never commit to git!)
5. **Updates**: Regularly update Docker images

## Cost Breakdown

| Service | Monthly Cost |
|---------|-------------|
| Oracle OCI | $0 (Always Free tier) |
| Backblaze B2 (500GB) | ~$3.50 |
| **Total** | **~$3.50** |

## Roadmap

- **Phase 1**: ✓ Immich + B2 storage
- **Phase 2**: Shared infrastructure (PostgreSQL, Redis)
- **Phase 3**: Nextcloud integration
- **Phase 4**: Additional services (Jellyfin, Vaultwarden)
- **Phase 5**: Enhanced monitoring & automation

See `docs/architecture-and-strategy.md` for full details.
