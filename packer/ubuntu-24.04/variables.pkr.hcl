########################################################
# Packer Variables for Ubuntu 24.04 LTS Proxmox Template
# with autoinstall + cloud-init + Docker + Grafana Alloy
########################################################

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

variable "tags" {
  type        = string
  description = "The tags to set. This is a semicolon separated list. For example, debian-12;template."
  default     = "packer;ubuntu"
}

########################################################
# --- System configuration ---
########################################################

variable "hostname" {
  type    = string
  default = "ubuntu2404"
}

variable "locale" {
  type    = string
  default = "en_US.UTF-8"
}

variable "keyboard_layout" {
  type    = string
  default = "us"
}

variable "keyboard_variant" {
  type    = string
  default = "intl"
}

variable "timezone" {
  type    = string
  default = "Europe/Lisbon"
}

variable "packages" {
  type = list(string)
  default = [
    "qemu-guest-agent",
    "curl",
    "vim",
    "net-tools",
    "jq",
    "mc",
    "sudo",
    "ca-certificates",
    "gnupg"
  ]
  description = "List of additional packages to install during autoinstall"
}

variable "users" {
  type = list(object({
    name                = string
    groups              = list(string)
    shell               = string
    sudo                = string
    lock_passwd         = bool
    ssh_authorized_keys = list(string)
  }))
  default = [
    {
      name        = "bcochofel"
      groups      = ["sudo", "docker"]
      shell       = "/bin/bash"
      sudo        = "ALL=(ALL) NOPASSWD:ALL"
      lock_passwd = false
      ssh_authorized_keys = [
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIEZGQwHOs8V9ndmLn3NuQXxuD0Ht4zaz+c6/WaEMAA6S bcochofel@NUC12WSHi7",
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIF4ljT5iXt1VgWML2ef+2Go6cN07gZLhl+hBZZhU9xYc bruno cochofel@NUC12WSHi7"
      ]
    }
  ]
}

variable "ssh_authorized_keys" {
  type        = list(string)
  description = "Global SSH authorized keys for default users"
  default     = []
}

########################################################
# --- Storage Configuration ---
########################################################

variable "storage_config" {
  type        = string
  description = <<EOT
YAML-formatted storage configuration block for Ubuntu Autoinstall.
This is injected directly into user-data under the 'storage:' key.
Example (LVM-based):

storage_config = <<EOF
layout:
  name: lvm
EOF
EOT

  # Default: Use an LVM layout (Ubuntu standard)
  default = <<EOF
layout:
  name: lvm
  sizing-policy: all
EOF
}

########################################################
# --- Networking, NTP & Proxy ---
########################################################

variable "use_proxy" {
  type        = bool
  description = "Whether to configure system-wide proxy settings"
  default     = false
}

variable "http_proxy" {
  type        = string
  description = "HTTP proxy address (e.g. http://proxy.example.com:8080)"
  default     = ""
}

variable "https_proxy" {
  type        = string
  description = "HTTPS proxy address"
  default     = ""
}

variable "no_proxy" {
  type        = string
  description = "Comma-separated list of domains or IPs to exclude from proxy"
  default     = "localhost,127.0.0.1"
}

variable "ntp_servers" {
  type        = list(string)
  description = "List of NTP servers to use"
  default     = ["0.ubuntu.pool.ntp.org", "1.ubuntu.pool.ntp.org"]
}

########################################################
# --- Grafana Alloy ---
########################################################

variable "use_alloy" {
  type        = bool
  description = "Whether to install and configure Grafana Alloy"
  default     = false
}

variable "alloy_version" {
  type        = string
  description = "Version of Grafana Alloy to install (e.g. v1.1.0)"
  default     = "v1.1.0"
}

variable "prometheus_endpoints" {
  type        = list(string)
  description = "List of Prometheus remote_write or scrape endpoints"
  default     = []
}

variable "loki_endpoints" {
  type        = list(string)
  description = "List of Loki log ingestion endpoints"
  default     = []
}
