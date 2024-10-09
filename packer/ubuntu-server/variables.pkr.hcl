variable "pm_api_url" {
  type        = string
  description = "URL to the Proxmox API"
  default     = "https:127.0.0.1:8006/api2/json"
}

variable "pm_api_token_id" {
  type        = string
  description = "Username when authenticating to Proxmox, including the realm."
  sensitive   = true
  default     = "packer@pve!packer-automation"
}

variable "pm_api_token_secret" {
  type        = string
  description = "Token for authenticating API calls."
  sensitive   = true
  default     = "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
}

variable "ssh_username" {
  type        = string
  description = "Username to use for SSH."
  sensitive   = true
  default     = "johndoe"
}

variable "ssh_private_key_file" {
  type        = string
  description = "Private key file to use for SSH."
  sensitive   = true
  default     = "~/.ssh/id_ed25519"
}
