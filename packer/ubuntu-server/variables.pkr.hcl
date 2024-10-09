variable "pm_api_url" {
  type        = string
  description = "URL to the Proxmox API"
}

variable "pm_api_token_id" {
  type        = string
  description = "Username when authenticating to Proxmox, including the realm."
  sensitive   = true
}

variable "pm_api_token_secret" {
  type        = string
  description = "Token for authenticating API calls."
  sensitive   = true
}
