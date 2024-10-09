packer {
  required_version = ">= 1.7.0, < 2.0.0"

  required_plugins {
    proxmox = {
      version = ">= 1.2.0"
      source  = "github.com/hashicorp/proxmox"
    }
  }
}
