# Self-Hosted Immich Server on Oracle ARM Instance

## Overview
A self-hosted photo management server using Docker on Oracle's 24GB memory ARM instance. Includes BusyBox monitoring to prevent termination.

## Requirements
- Oracle cloud account with ARM instance (24GB memory)
- SSH access to instance
- Basic knowledge of Docker

## Architecture
- **Immich Service**: Photo management application in Docker container
- **BusyBox Monitor**: Lightweight process to prevent instance termination
- **Hybrid Storage**: Backblaze B2 for original photos, OCI block volume for thumbnails

## Infrastructure Architecture Diagram

### Hybrid Storage Architecture

```
┌─────────────────────────────────────────────────────────────────────────────────┐
│                              INTERNET                                             │
└─────────────────────────────────────────────────────────────────────────────────┘
                                        │
                    ┌───────────────────┴───────────────────┐
                    │                                       │
                    ▼                                       ▼
┌──────────────────────────────────┐          ┌──────────────────────────────┐
│      Oracle Cloud (OCI)          │          │      Backblaze B2            │
│                                  │          │                              │
│  ┌────────────────────────────┐  │          │  ┌────────────────────────┐  │
│  │  Compute Instance (ARM)    │  │          │  │  immich-photos Bucket  │  │
│  │  VM.Standard.A1.Flex       │  │          │  │                        │  │
│  │  4 OCPUs | 24GB RAM        │  │          │  │  ┌──────────────────┐  │  │
│  │                            │  │          │  │  │  Original Photos │  │  │
│  │  ┌──────────────────────┐  │  │          │  │  │  RAW, JPG, etc.  │  │  │
│  │  │ Docker Environment   │  │  │          │  │  └──────────────────┘  │  │
│  │  │                      │  │  │          │  │                        │  │
│  │  │ ┌─────────────────┐  │  │  │          │  └────────────────────────┘  │
│  │  │ │ Immich Container│  │  │  │          │                              │
│  │  │ │                 │  │  │  │          └──────────────────────────────┘
│  │  │ │ ┌───────────┐   │  │  │  │                        ▲
│  │  │ │ │Thumbnails │   │  │  │  │                        │
│  │  │ │ │  Cache    │   │  │  │  │         rclone mount   │
│  │  │ │ │  (local)  │   │  │  │  │         (read-only)    │
│  │  │ │ └─────┬─────┘   │  │  │  │                        │
│  │  │ │       │         │  │  │  └────────────────────────┘
│  │  │ │ ┌─────┴─────┐   │  │  │
│  │  │ │ │  B2 Mount │   │  │  │     Fast Access Pattern:
│  │  │ │ │  (ro)     │◄──┼──┼──┼───── Thumbnails served locally
│  │  │ │ └───────────┘   │  │  │     Photos streamed from B2
│  │  │ └─────────────────┘  │  │
│  │  └──────────────────────┘  │
│  │                            │
│  │  ┌──────────────────────┐  │
│  │  │ BusyBox Monitor      │  │
│  │  │ (Health Check 60s)   │  │
│  │  └──────────────────────┘  │
│  └────────────────────────────┘
│             │
│  ┌──────────┴──────────┐
│  │ Block Volume (200GB)│
│  │ Thumbnails Only     │
│  └─────────────────────┘
└──────────────────────────────────┘
```

### Storage Flow

```
User Upload ──┬──► Original Photo ──► Backblaze B2 (Permanent Storage)
              │
              └──► Thumbnails ─────► OCI Block Volume (200GB Cache)
                                           │
                                           ▼
                              ┌──────────────────────┐
                              │   Immich Web UI      │
                              │   (Fast Serving)     │
                              └──────────────────────┘
```

### Generating Infrastructure Diagrams

You can visualize the OpenTofu infrastructure using these commands:

**1. Generate Resource Graph (DOT format):**
```bash
cd infra
tofu init
tofu plan -out=tfplan
tofu graph -plan=tfplan > graph.dot
```

**2. Convert to PNG (requires Graphviz):**
```bash
# Install Graphviz first
# macOS: brew install graphviz
# Ubuntu: sudo apt-get install graphviz

dot -Tpng graph.dot -o infrastructure-graph.png
```

**3. Generate JSON representation for other tools:**
```bash
tofu show -json tfplan > plan.json
```

**4. View simplified resource list:**
```bash
tofu state list
```

## Getting Started
1. **SSH into your Oracle instance**
2. **Clone this repository**
   ```bash
   git clone https://github.com/your-repo/immich-oracle-setup.git
   cd immich-oracle-setup
   ```
3. **Run setup script (on server)**
   ```bash
   ./server/setup.sh
   ```
4. **Start services (on server)**
   ```bash
   ./server/start-services.sh
   ```

## Directory Structure
- `server/` - Scripts to run on the Oracle server (setup, start/stop services)
- `local/` - Scripts to run on your local machine (SSH helpers, etc.)
- `infra/` - OpenTofu/Terraform infrastructure code for Oracle Cloud

## Infrastructure Setup (OpenTofu)

The `infra/` directory contains OpenTofu code to provision all Oracle Cloud Infrastructure:

### Prerequisites
- [OpenTofu](https://opentofu.org/) or Terraform installed
- OCI CLI configured with API keys
- SSH key pair generated

### Setup Steps

1. **Configure OCI credentials:**
   ```bash
   cd infra
   cp terraform.tfvars.example terraform.tfvars
   # Edit terraform.tfvars with your OCI credentials
   ```

2. **Initialize OpenTofu:**
   ```bash
   tofu init
   ```

3. **Plan the infrastructure:**
   ```bash
   tofu plan -out=tfplan
   ```

4. **Apply the infrastructure:**
   ```bash
   tofu apply tfplan
   ```

5. **Get connection details:**
   ```bash
   tofu output
   ```

This will create:
- Virtual Cloud Network (VCN) with subnet
- Internet Gateway and Route Table
- Security List (firewall rules for SSH and port 8080)
- ARM compute instance (4 OCPUs, 24GB RAM)
- Block volume (200GB) for thumbnails and cache

## Backblaze B2 Setup

### Why Hybrid Storage?
- **Thumbnails on OCI**: Frequently accessed, need fast I/O
- **Originals on B2**: Cost-effective long-term storage (~$6/TB/month)
- **Reduced API calls**: Thumbnails cached locally, minimizing B2 transactions

### Setup Steps

1. **Create a Backblaze B2 account**: https://www.backblaze.com/b2/cloud-storage.html

2. **Create a bucket**:
   - Name it `immich-photos` (or your preferred name)
   - Set to private

3. **Generate Application Keys**:
   - Go to App Keys in B2 console
   - Create a new key with read/write access to your bucket
   - Save the Key ID and Application Key

4. **Configure the server**:
   ```bash
   cd server
   cp .env.example .env
   # Edit .env with your B2 credentials
   ```

5. **Run setup**:
   The setup script will automatically:
   - Install rclone
   - Configure B2 mount
   - Mount B2 bucket as read-only volume
   - Set up local directories for thumbnails
5. **Access Immich at** `http://<your-instance-ip>:8080`

## Notes
- Ensure your security group allows port 8080
- The BusyBox container runs a health check every 60 seconds
- **Storage Architecture**:
  - Original photos stored in Backblaze B2 (~$6/TB/month)
  - Thumbnails cached on 200GB OCI block volume for fast access
  - B2 bucket mounted via rclone with read-only access to Immich
- **Cost Optimization**: Local thumbnail cache minimizes B2 API calls (Class B transactions)
- **Backup Strategy**: B2 provides automatic redundancy and versioning for original photos
