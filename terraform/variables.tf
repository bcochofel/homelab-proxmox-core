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

variable "dns_hostname" {
  type        = string
  description = "DNS Server hostname"
  default     = "dns1"
}

variable "dns_root_password" {
  type        = string
  description = "LXC root password for DNS server."
  sensitive   = true
}

variable "ssh_pubkeys" {
  type        = string
  description = "SSH public keys for connecting to LXC container."
  default     = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIEZGQwHOs8V9ndmLn3NuQXxuD0Ht4zaz+c6/WaEMAA6S bcochofel@NUC12WSHi7"
}

variable "gateway" {
  type        = string
  description = "Network Gateway"
  default     = "192.168.68.1"
}

variable "dns_ip" {
  type        = string
  description = "The DNS server IP address used by the container."
  default     = "192.168.68.2"
}

variable "nameserver" {
  type        = string
  description = "Nameserver to use"
  default     = "8.8.8.8"
}

variable "searchdomain" {
  type        = string
  description = "Sets the DNS search domains for the container."
}

variable "network" {
  type        = string
  description = "Network CIDR"
}

variable "bind9_enabled" {
  type        = bool
  description = "Flag to enable or disable the BIND9 integration."
  default     = false
}

variable "workstation_enabled" {
  type        = bool
  description = "Flag to enable or disable the Workstation integration."
  default     = false
}
