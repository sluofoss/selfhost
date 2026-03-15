variable "tenancy_ocid" {
  description = "OCID of your OCI tenancy"
  type        = string
}

variable "user_ocid" {
  description = "OCID of your OCI user"
  type        = string
}

variable "fingerprint" {
  description = "Fingerprint of your OCI API key"
  type        = string
}

variable "private_key_path" {
  description = "Path to your OCI API private key"
  type        = string
}

variable "region" {
  description = "OCI region (e.g., us-ashburn-1)"
  type        = string
}

variable "compartment_ocid" {
  description = "OCID of compartment to create resources in"
  type        = string
}

variable "ssh_public_key_path" {
  description = "Path to SSH public key file for instance access"
  type        = string
  default     = "~/.ssh/id_ed25519.pub"
}

variable "repo_url" {
  description = "Git repository URL to clone on the server (must be public)"
  type        = string
  default     = "https://github.com/your-username/selfhost.git"
}

variable "instance_name" {
  description = "Name of the compute instance"
  type        = string
  default     = "selfhost-server"
}

variable "vcn_cidr" {
  description = "CIDR block for VCN"
  type        = string
  default     = "10.0.0.0/16"
}

variable "subnet_cidr" {
  description = "CIDR block for subnet"
  type        = string
  default     = "10.0.0.0/24"
}

variable "ocpus" {
  description = "Number of OCPUs for ARM instance"
  type        = number
  default     = 4
}

variable "memory_in_gbs" {
  description = "Memory in GB for ARM instance (max 24 for free tier)"
  type        = number
  default     = 24
}

variable "boot_volume_size_in_gbs" {
  description = "Boot volume size in GB"
  type        = number
  default     = 120
}

variable "thumbnail_volume_size_in_gbs" {
  description = "Block volume size for data (thumbnails, DB, caches) in GB"
  type        = number
  default     = 200
}

variable "restrict_web_to_cloudflare" {
  description = "When true, only allow HTTP/HTTPS ingress from the Cloudflare provider's current IPv4 ranges. SSH is controlled separately."
  type        = bool
  default     = false
}

variable "ssh_allowed_cidrs" {
  description = "CIDR ranges allowed to access SSH. Defaults to world-open until SSH is moved behind a tighter admin path."
  type        = list(string)
  default     = ["0.0.0.0/0"]
}
