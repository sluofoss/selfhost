#cloud-config
# Cloud-init configuration for selfhost OCI instance
# This runs on first boot to set up the base system.
# After cloud-init completes, the user must:
#   1. SSH in and configure .env files with real credentials
#   2. Run ./scripts/setup/install.sh for B2 mount, cron jobs, Docker pull

# Disable automatic package operations to prevent APT lock conflicts
package_update: false
package_upgrade: false

# We'll handle package installation manually in runcmd with proper lock handling

# Add ubuntu user to fuse group for rclone mounts
groups:
  - docker

users:
  - default

runcmd:
  # ==========================================
  # WAIT FOR SYSTEM TO SETTLE AND HANDLE APT LOCKS
  # ==========================================
  - echo "Cloud-init starting - waiting for system to settle..."
  - sleep 30
  
  # Stop any running unattended-upgrades to prevent APT lock conflicts
  - systemctl stop unattended-upgrades.service || true
  - systemctl disable unattended-upgrades.service || true
  - pkill -f unattended-upgrade || true
  
  # Install packages and Docker in one consolidated block
  - |
    # Function to wait for APT lock to be released
    wait_for_apt_lock() {
      echo "Waiting for APT lock to be released..."
      max_attempts=30
      attempt=1
      
      while [ $attempt -le $max_attempts ]; do
        if fuser /var/lib/dpkg/lock-frontend >/dev/null 2>&1 || 
           fuser /var/lib/apt/lists/lock >/dev/null 2>&1 || 
           fuser /var/cache/apt/archives/lock >/dev/null 2>&1; then
          echo "APT is locked, waiting... (attempt $attempt/$max_attempts)"
          sleep 10
          attempt=$((attempt + 1))
        else
          echo "APT lock released!"
          return 0
        fi
      done
      
      echo "WARNING: APT lock timeout after $max_attempts attempts"
      return 1
    }
    
    echo "Installing base packages..."
    wait_for_apt_lock
    apt-get update -y
    
    # Install required packages with retry logic
    packages="apt-transport-https ca-certificates curl gnupg lsb-release software-properties-common rclone fuse apache2-utils inotify-tools cron ufw git"
    max_attempts=3
    attempt=1
    
    while [ $attempt -le $max_attempts ]; do
      echo "Installing packages (attempt $attempt/$max_attempts)..."
      wait_for_apt_lock
      
      if apt-get install -y $packages; then
        echo "Package installation successful!"
        break
      else
        echo "Package installation failed, retrying in 30 seconds..."
        sleep 30
        attempt=$((attempt + 1))
        
        if [ $attempt -gt $max_attempts ]; then
          echo "ERROR: Package installation failed after $max_attempts attempts"
        fi
      fi
    done
    
    echo "Installing Docker..."
    # Add Docker GPG key
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
    
    # Get architecture and Ubuntu codename
    ARCH=$(dpkg --print-architecture)
    CODENAME=$(lsb_release -cs)
    
    # Add Docker repository
    echo "deb [arch=$ARCH signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $CODENAME stable" > /etc/apt/sources.list.d/docker.list
    
    # Update package lists
    wait_for_apt_lock
    apt-get update -y
    
    # Install Docker with retry logic
    max_attempts=3
    attempt=1
    while [ $attempt -le $max_attempts ]; do
      echo "Installing Docker (attempt $attempt/$max_attempts)..."
      wait_for_apt_lock
      
      if apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin; then
        echo "Docker installation successful!"
        break
      else
        echo "Docker installation failed, retrying in 30 seconds..."
        sleep 30
        attempt=$((attempt + 1))
        
        if [ $attempt -gt $max_attempts ]; then
          echo "ERROR: Docker installation failed after $max_attempts attempts"
          echo "Continuing with remaining setup tasks..."
          break
        fi
      fi
    done
    
    # Configure Docker
    usermod -aG docker ubuntu
    systemctl enable docker
    systemctl start docker
    
    # Verify Docker installation
    if command -v docker >/dev/null 2>&1; then
      docker --version
      echo "Docker installation complete!"
    else
      echo "Docker installation may have failed"
    fi

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
    echo "Cloning repository..."
    if [ ! -d /home/ubuntu/selfhost ]; then
      max_attempts=3
      attempt=1
      repo_url="${repo_url}"
      
      while [ $attempt -le $max_attempts ]; do
        echo "Cloning repository (attempt $attempt/$max_attempts)..."
        
        if git clone "$repo_url" /home/ubuntu/selfhost; then
          echo "Repository clone successful!"
          chown -R ubuntu:ubuntu /home/ubuntu/selfhost
          
          # Verify the clone was successful
          if [ -f "/home/ubuntu/selfhost/README.md" ] || [ -d "/home/ubuntu/selfhost/server" ]; then
            echo "Repository verification successful!"
            break
          else
            echo "Repository clone appears incomplete, retrying..."
            rm -rf /home/ubuntu/selfhost
            sleep 10
            attempt=$((attempt + 1))
          fi
        else
          echo "Repository clone failed, retrying in 30 seconds..."
          rm -rf /home/ubuntu/selfhost 2>/dev/null || true
          sleep 30
          attempt=$((attempt + 1))
        fi
        
        if [ $attempt -gt $max_attempts ]; then
          echo "ERROR: Repository clone failed after $max_attempts attempts"
          echo "Repository URL: $repo_url"
          echo "Please check if the repository is public and accessible"
          # Don't exit here, continue with setup
          return 1
        fi
      done
    else
      echo "Repository directory already exists, skipping clone"
      chown -R ubuntu:ubuntu /home/ubuntu/selfhost
    fi
    
    # Final verification that repository exists and has expected structure
    if [ ! -d "/home/ubuntu/selfhost/server" ]; then
      echo "ERROR: Repository clone failed or incomplete - /home/ubuntu/selfhost/server not found"
      echo "Attempting alternative clone method..."
      rm -rf /home/ubuntu/selfhost 2>/dev/null || true
      if git clone "$repo_url" /home/ubuntu/selfhost; then
        chown -R ubuntu:ubuntu /home/ubuntu/selfhost
        echo "Alternative clone successful!"
      else
        echo "ERROR: All clone attempts failed. Manual intervention required."
        return 1
      fi
    fi

  # ==========================================
  # COPY .ENV.EXAMPLE FILES AS PLACEHOLDERS
  # ==========================================
  - |
    echo "Setting up environment configuration files..."
    if [ -d "/home/ubuntu/selfhost/server" ]; then
      cd /home/ubuntu/selfhost/server
      
      success_count=0
      total_files=4
      
      for envfile in .env.example traefik/.env.example immich/.env.example monitoring/.env.example; do
        dir=$(dirname "$envfile")
        target="$dir/.env"
        
        # Ensure the target directory exists
        mkdir -p "$dir" 2>/dev/null || true
        
        if [ -f "$envfile" ]; then
          if [ ! -f "$target" ]; then
            if cp "$envfile" "$target" && chown ubuntu:ubuntu "$target" && chmod 644 "$target"; then
              echo "[OK] Created $target from $envfile"
              success_count=$((success_count + 1))
            else
              echo "[ERROR] Failed to create $target"
            fi
          else
            echo "[SKIP] $target already exists"
            success_count=$((success_count + 1))
          fi
        else
          echo "[WARN] Template $envfile not found, creating empty .env file"
          touch "$target" && chown ubuntu:ubuntu "$target" && chmod 644 "$target"
          success_count=$((success_count + 1))
        fi
      done
      
      echo "Environment file setup complete: $success_count/$total_files files processed"
      
      # Additional verification
      if [ $success_count -eq $total_files ]; then
        echo "[OK] All environment files successfully created"
      else
        echo "[WARN] Not all environment files were created successfully"
      fi
    else
      echo "ERROR: /home/ubuntu/selfhost/server directory not found"
      echo "Repository clone failed - continuing with remaining setup"
      # Don't exit, continue with other setup tasks
      return 1
    fi

  # ==========================================
  # CONFIGURE FIREWALL
  # ==========================================
  - |
    echo "Configuring UFW firewall..."
    ufw --force reset
    ufw default deny incoming
    ufw default allow outgoing
    ufw allow 22/tcp
    ufw allow 80/tcp
    ufw allow 443/tcp
    echo "y" | ufw enable
    
    echo "Firewall configuration complete!"
    ufw status verbose
  
  # ==========================================
  # FINAL VERIFICATION AND STATUS
  # ==========================================
  - |
    echo "=========================================="
    echo "CLOUD-INIT VERIFICATION"
    echo "=========================================="
    
    # Check critical services
    echo "Checking Docker installation..."
    if docker --version >/dev/null 2>&1; then
      echo "[OK] Docker installed: $(docker --version)"
    else
      echo "[ERROR] Docker installation failed"
    fi
    
    # Check repository
    echo "Checking repository clone..."
    if [ -d "/home/ubuntu/selfhost" ]; then
      echo "[OK] Repository cloned to /home/ubuntu/selfhost"
      echo "  Contents: $(ls -la /home/ubuntu/selfhost | wc -l) items"
    else
      echo "[ERROR] Repository not found"
    fi
    
    # Check data volume
    echo "Checking data volume..."
    if mountpoint -q /data; then
      echo "[OK] Data volume mounted: $(df -h /data | tail -1)"
    else
      echo "[ERROR] Data volume not mounted properly"
    fi
    
    # Check environment files
    echo "Checking environment files..."
    env_count=0
    for env_file in "/home/ubuntu/selfhost/server/.env" "/home/ubuntu/selfhost/server/traefik/.env" "/home/ubuntu/selfhost/server/immich/.env"; do
      if [ -f "$env_file" ]; then
        env_count=$((env_count + 1))
      fi
    done
    echo "[OK] Environment files created: $env_count/3"
    
    # Check firewall
    echo "Checking firewall..."
    if ufw status | grep -q "Status: active"; then
      echo "[OK] Firewall active and configured"
    else
      echo "[ERROR] Firewall not properly configured"
    fi
    
    echo "=========================================="
    echo "CLOUD-INIT SETUP COMPLETE!"
    echo "=========================================="
    
    # Final verification - don't fail if some components had issues
    failed_components=0
    
    # Check Docker
    if ! command -v docker >/dev/null 2>&1; then
      echo "[WARNING] Docker not found in PATH"
      failed_components=$((failed_components + 1))
    fi
    
    # Check repository
    if [ ! -d "/home/ubuntu/selfhost" ]; then
      echo "[WARNING] Repository not cloned"
      failed_components=$((failed_components + 1))
    fi
    
    # Check data volume
    if ! mountpoint -q /data; then
      echo "[WARNING] Data volume not mounted"
      failed_components=$((failed_components + 1))
    fi
    
    if [ $failed_components -eq 0 ]; then
      echo "[SUCCESS] All components verified successfully!"
      exit 0
    else
      echo "[WARNING] $failed_components components had issues but setup completed"
      echo "Manual verification may be required"
      exit 0
    fi

final_message: |
  Cloud-init setup complete!
  
  Next steps:
    1. SSH to this server: ssh -i <your-key> ubuntu@$(curl -s ifconfig.me)
    2. Configure .env files: cd ~/selfhost/server && nano .env
    3. Run post-config setup: ./scripts/setup/install.sh
    4. Start services: ./start.sh
