output "instance_public_ip" {
  description = "Public IP address of the Immich server"
  value       = oci_core_instance.immich_instance.public_ip
}

output "instance_private_ip" {
  description = "Private IP address of the Immich server"
  value       = oci_core_instance.immich_instance.private_ip
}

output "instance_ocid" {
  description = "OCID of the compute instance"
  value       = oci_core_instance.immich_instance.id
}

output "immich_url" {
  description = "URL to access Immich after setup"
  value       = "http://${oci_core_instance.immich_instance.public_ip}:8080"
}

output "ssh_command" {
  description = "SSH command to connect to the instance"
  value       = "ssh ubuntu@${oci_core_instance.immich_instance.public_ip}"
}
