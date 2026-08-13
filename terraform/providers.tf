# bpg/proxmox provider configuration.
#
# Auth via API token (recommended). See docs/TERRAFORM.md "Proxmox user &
# API token" for the full scoped-role pveum commands (role TerraformRole,
# not the built-in PVEVMAdmin):
#   pveum user add terraform@pve
#   pveum aclmod / -user terraform@pve -role TerraformRole
#   pveum user token add terraform@pve terraform-automation --privsep 0
# Then export the secret (HCP workspace var or local env):
#   TF_VAR_proxmox_api_token = "terraform@pve!terraform-automation=xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
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
