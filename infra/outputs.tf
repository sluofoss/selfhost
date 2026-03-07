output "instance_public_ip" {
  description = "Public IP address of the server (reserved, persists across reboots)"
  value       = oci_core_public_ip.immich_reserved_ip.ip_address
}

output "instance_private_ip" {
  description = "Private IP address of the server"
  value       = oci_core_instance.immich_instance.private_ip
}

output "instance_ocid" {
  description = "OCID of the compute instance"
  value       = oci_core_instance.immich_instance.id
}

output "reserved_public_ip_ocid" {
  description = "OCID of the reserved public IP (for DNS configuration)"
  value       = oci_core_public_ip.immich_reserved_ip.id
}

output "ssh_command" {
  description = "SSH command to connect to the instance"
  value       = "ssh -i ${replace(var.ssh_public_key_path, ".pub", "")} ubuntu@${oci_core_public_ip.immich_reserved_ip.ip_address}"
}

output "next_steps" {
  description = "What to do after provisioning"
  value       = <<-EOT
    
    Cloud-init is now provisioning the server. Wait ~5 minutes, then:
    
    1. SSH in:
       ${format("ssh -i %s ubuntu@%s", replace(var.ssh_public_key_path, ".pub", ""), oci_core_public_ip.immich_reserved_ip.ip_address)}
    
    2. Check cloud-init status:
       cloud-init status
    
    3. Configure .env files:
       cd ~/selfhost/server
       nano .env            # B2 credentials, domain
       nano traefik/.env    # ACME email, domain
       nano immich/.env     # DB password, domain
       nano monitoring/.env # Grafana credentials
    
    4. Run post-config setup:
       ./scripts/setup/install.sh
    
    5. Start services:
       ./start.sh
  EOT
}
