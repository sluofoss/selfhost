terraform {
  required_providers {
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "~> 4.0"
    }

    oci = {
      source  = "oracle/oci"
      version = "~> 5.0"
    }
  }
}

# Supply CLOUDFLARE_API_TOKEN when restrict_web_to_cloudflare is enabled.
provider "cloudflare" {}

provider "oci" {
  tenancy_ocid     = var.tenancy_ocid
  user_ocid        = var.user_ocid
  fingerprint      = var.fingerprint
  private_key_path = var.private_key_path
  region           = var.region
}
