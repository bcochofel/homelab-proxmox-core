terraform {
  required_version = "~> 1.9.0"

  required_providers {
    proxmox = {
      source  = "Telmate/proxmox"
      version = "3.0.1-rc4"
    }
    random = {
      source  = "hashicorp/random"
      version = "3.6.3"
    }
  }

  cloud {
    organization = "homelab-bcochofel-com"

    workspaces {
      name = "core-components"
    }
  }
}
