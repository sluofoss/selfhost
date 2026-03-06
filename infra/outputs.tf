output "instance_public_ip" {
  description = "Public IP address of the Immich server (reserved, persists across reboots)"
  value       = oci_core_public_ip.immich_reserved_ip.ip_address
}

output "instance_private_ip" {
  description = "Private IP address of the Immich server"
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

output "immich_url" {
  description = "URL to access Immich after setup"
  value       = "http://${oci_core_public_ip.immich_reserved_ip.ip_address}:8080"
}

output "ssh_command" {
  description = "SSH command to connect to the instance"
  value       = "ssh ubuntu@${oci_core_public_ip.immich_reserved_ip.ip_address}"
}
