terraform {
  required_version = "> 1.9.0, < 2.0"

  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = "~> 0.85" # pin minor — bpg iterates fast
    }
    local = {
      source  = "hashicorp/local"
      version = "2.9.0"
    }
  }

  # HCP Terraform. Separate workspace per workload. State-only (workspace
  # execution mode = Local); applied with OpenTofu from a laptop.
  # `hostname` is required by OpenTofu, which has no default for the cloud
  # backend; app.terraform.io is also Terraform's default, so it's a no-op
  # there.
  cloud {
    hostname     = "app.terraform.io"
    organization = "homelab-bcochofel-com"

    workspaces {
      name = "core-caddy"
    }
  }
}
