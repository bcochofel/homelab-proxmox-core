variable "pm_api_url" {
  type        = string
  description = "This is the target Proxmox API endpoint."
}

variable "pm_api_token_id" {
  type        = string
  description = "This is an API token you have previously created for a specific user."
  sensitive   = true
}

variable "pm_api_token_secret" {
  type        = string
  description = "This uuid is only available when the token was initially created."
  sensitive   = true
}

variable "lxc_password" {
  type        = string
  description = "Sets the root password inside the container."
  sensitive   = true
}

variable "lxc_ip" {
  type        = string
  description = "IP for the LXC"
  default     = "192.168.68.252"
}
