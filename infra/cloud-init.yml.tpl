#cloud-config
# Cloud-init configuration for selfhost OCI instance
# This runs on first boot to set up the base system.
# After cloud-init completes, the user must:
#   1. SSH in and configure .env files with real credentials
#   2. Run ./scripts/setup/install.sh for B2 mount, cron jobs, Docker pull

package_update: true
package_upgrade: true

packages:
  - apt-transport-https
  - ca-certificates
  - curl
  - gnupg
  - lsb-release
  - software-properties-common
  - rclone
  - fuse
  - apache2-utils
  - inotify-tools
  - cron
  - ufw
  - git

# Add ubuntu user to fuse group for rclone mounts
groups:
  - docker

users:
  - default

runcmd:
  # ==========================================
  # INSTALL DOCKER
  # ==========================================
  - curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
  - echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" > /etc/apt/sources.list.d/docker.list
  - apt-get update
  - apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
  - usermod -aG docker ubuntu
  - systemctl enable docker
  - systemctl start docker

  # ==========================================
  # FORMAT AND MOUNT BLOCK VOLUME
  # ==========================================
  # Wait for block volume to be attached
  - |
    for i in $(seq 1 30); do
      if [ -e /dev/sdb ]; then
        break
      fi
      echo "Waiting for block volume to attach... ($i/30)"
      sleep 10
    done

  # Format only if not already formatted
  - |
    if [ -e /dev/sdb ]; then
      if ! blkid /dev/sdb | grep -q ext4; then
        echo "Formatting block volume..."
        mkfs.ext4 /dev/sdb
      fi
      mkdir -p /data
      mount /dev/sdb /data
      # Add to fstab for persistence across reboots
      if ! grep -q '/dev/sdb' /etc/fstab; then
        echo '/dev/sdb /data ext4 defaults,nofail 0 2' >> /etc/fstab
      fi
      chown ubuntu:ubuntu /data
    else
      echo "WARNING: Block volume /dev/sdb not found, creating /data on boot volume"
      mkdir -p /data
      chown ubuntu:ubuntu /data
    fi

  # ==========================================
  # CREATE DIRECTORY STRUCTURE
  # ==========================================
  - mkdir -p /data/immich/{thumbnails,cache,b2-mount}
  - mkdir -p /data/backups/{postgres,configs,weekly}
  - mkdir -p /data/monitoring
  - chown -R ubuntu:ubuntu /data

  # ==========================================
  # CLONE REPOSITORY
  # ==========================================
  - |
    if [ ! -d /home/ubuntu/selfhost ]; then
      git clone ${repo_url} /home/ubuntu/selfhost
      chown -R ubuntu:ubuntu /home/ubuntu/selfhost
    fi

  # ==========================================
  # COPY .ENV.EXAMPLE FILES AS PLACEHOLDERS
  # ==========================================
  - |
    cd /home/ubuntu/selfhost/server
    for envfile in .env.example traefik/.env.example immich/.env.example monitoring/.env.example; do
      dir=$(dirname "$envfile")
      target="$dir/.env"
      if [ -f "$envfile" ] && [ ! -f "$target" ]; then
        cp "$envfile" "$target"
        chown ubuntu:ubuntu "$target"
      fi
    done

  # ==========================================
  # CONFIGURE FIREWALL
  # ==========================================
  - ufw default deny incoming
  - ufw default allow outgoing
  - ufw allow 22/tcp
  - ufw allow 80/tcp
  - ufw allow 443/tcp
  - echo "y" | ufw enable

final_message: |
  Cloud-init setup complete!
  
  Next steps:
    1. SSH to this server: ssh -i <your-key> ubuntu@$(curl -s ifconfig.me)
    2. Configure .env files: cd ~/selfhost/server && nano .env
    3. Run post-config setup: ./scripts/setup/install.sh
    4. Start services: ./start.sh
