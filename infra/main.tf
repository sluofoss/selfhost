# Get availability domains
data "oci_identity_availability_domains" "ads" {
  compartment_id = var.tenancy_ocid
}

# Get the latest Ubuntu 22.04 LTS image
data "oci_core_images" "ubuntu_image" {
  compartment_id           = var.compartment_ocid
  operating_system         = "Canonical Ubuntu"
  operating_system_version = "22.04"
  shape                    = "VM.Standard.A1.Flex"
  sort_by                  = "TIMECREATED"
  sort_order               = "DESC"
}

# Virtual Cloud Network
resource "oci_core_vcn" "immich_vcn" {
  compartment_id = var.compartment_ocid
  cidr_block     = var.vcn_cidr
  display_name   = "immich-vcn"
  dns_label      = "immichvcn"
}

# Internet Gateway
resource "oci_core_internet_gateway" "immich_igw" {
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.immich_vcn.id
  display_name   = "immich-internet-gateway"
  enabled        = true
}

# Route Table
resource "oci_core_route_table" "immich_route_table" {
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.immich_vcn.id
  display_name   = "immich-route-table"

  route_rules {
    destination       = "0.0.0.0/0"
    destination_type  = "CIDR_BLOCK"
    network_entity_id = oci_core_internet_gateway.immich_igw.id
  }
}

# Security List (Firewall Rules)
resource "oci_core_security_list" "immich_security_list" {
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.immich_vcn.id
  display_name   = "immich-security-list"

  # SSH access
  ingress_security_rules {
    protocol    = "6" # TCP
    source      = "0.0.0.0/0"
    description = "SSH"
    tcp_options {
      min = 22
      max = 22
    }
  }

  # HTTP - Required for Let's Encrypt and Cloudflare
  ingress_security_rules {
    protocol    = "6" # TCP
    source      = "0.0.0.0/0"
    description = "HTTP"
    tcp_options {
      min = 80
      max = 80
    }
  }

  # HTTPS
  ingress_security_rules {
    protocol    = "6" # TCP
    source      = "0.0.0.0/0"
    description = "HTTPS"
    tcp_options {
      min = 443
      max = 443
    }
  }

  # Allow all outbound traffic
  egress_security_rules {
    protocol    = "all"
    destination = "0.0.0.0/0"
    description = "All outbound traffic"
  }
}

# Subnet
resource "oci_core_subnet" "immich_subnet" {
  compartment_id    = var.compartment_ocid
  vcn_id            = oci_core_vcn.immich_vcn.id
  cidr_block        = var.subnet_cidr
  display_name      = "immich-subnet"
  dns_label         = "immichsubnet"
  route_table_id    = oci_core_route_table.immich_route_table.id
  security_list_ids = [oci_core_security_list.immich_security_list.id]
}

# Compute Instance - ARM Ampere (Free Tier Eligible)
resource "oci_core_instance" "immich_instance" {
  compartment_id      = var.compartment_ocid
  availability_domain = data.oci_identity_availability_domains.ads.availability_domains[0].name
  display_name        = var.instance_name
  shape               = "VM.Standard.A1.Flex"

  shape_config {
    ocpus         = var.ocpus
    memory_in_gbs = var.memory_in_gbs
  }

  source_details {
    source_type             = "image"
    source_id               = data.oci_core_images.ubuntu_image.images[0].id
    boot_volume_size_in_gbs = var.boot_volume_size_in_gbs
  }

  create_vnic_details {
    subnet_id        = oci_core_subnet.immich_subnet.id
    assign_public_ip = false # We'll use a reserved public IP instead
    display_name     = "immich-vnic"
  }

  metadata = {
    ssh_authorized_keys = file(var.ssh_public_key_path)
    user_data = base64encode(templatefile("${path.module}/cloud-init.yml.tpl", {
      repo_url = var.repo_url
    }))
  }

  preserve_boot_volume = false
}

# Get the VNIC attachment for the instance
data "oci_core_vnic_attachments" "immich_vnic_attachments" {
  compartment_id = var.compartment_ocid
  instance_id    = oci_core_instance.immich_instance.id
}

# Get the VNIC details
data "oci_core_vnic" "immich_vnic" {
  vnic_id = data.oci_core_vnic_attachments.immich_vnic_attachments.vnic_attachments[0].vnic_id
}

# Get the private IPs for the VNIC
data "oci_core_private_ips" "immich_private_ips" {
  vnic_id = data.oci_core_vnic.immich_vnic.id
}

# Reserved Public IP - persists across instance stop/start
resource "oci_core_public_ip" "immich_reserved_ip" {
  compartment_id = var.compartment_ocid
  display_name   = "immich-reserved-public-ip"
  lifetime       = "RESERVED" # Reserved, not ephemeral

  # Associate with the instance's primary private IP
  private_ip_id = data.oci_core_private_ips.immich_private_ips.private_ips[0].id

  # Prevent accidental destruction - requires explicit removal
  lifecycle {
    prevent_destroy = true
  }
}

# Block Volume for Immich thumbnails and cache
# Original photos stored in Backblaze B2, thumbnails cached locally for fast access
resource "oci_core_volume" "immich_data_volume" {
  compartment_id      = var.compartment_ocid
  availability_domain = data.oci_identity_availability_domains.ads.availability_domains[0].name
  display_name        = "immich-thumbnails-volume"
  size_in_gbs         = var.thumbnail_volume_size_in_gbs

  freeform_tags = {
    "purpose" = "thumbnails-cache"
    "storage" = "oci-local"
    "photos"  = "backblaze-b2"
  }
}

resource "oci_core_volume_attachment" "immich_volume_attachment" {
  attachment_type = "paravirtualized"
  instance_id     = oci_core_instance.immich_instance.id
  volume_id       = oci_core_volume.immich_data_volume.id
}
