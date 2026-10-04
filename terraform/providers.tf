# bpg/proxmox provider configuration.
#
# Auth via API token, form user@realm!tokenid=secret, passed as
# TF_VAR_proxmox_api_token: bcochofel@pve!console (TofuApply role) through
# `tofu_rw`, or ai-agent@pve!ai-agent (AiAgentRO, read-only) through
# `hl_ro`. Roles, users and tokens: docs/CREDENTIALS.md.
provider "proxmox" {
  endpoint  = var.proxmox_endpoint
  api_token = var.proxmox_api_token
  insecure  = var.proxmox_insecure

  # Some operations (file uploads, certain disk ops) require SSH.
  # Cloning + cloud-init for our use case generally does not, but enable if needed.
  ssh {
    agent    = true
    username = var.proxmox_ssh_username
  }
}
