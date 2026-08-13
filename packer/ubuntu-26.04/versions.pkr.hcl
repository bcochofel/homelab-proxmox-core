packer {
  required_version = ">= 1.9.0, <= 2.0.0"

  required_plugins {
    proxmox = {
      version = ">= 1.1.8"
      source  = "github.com/hashicorp/proxmox"
    }
  }
}
