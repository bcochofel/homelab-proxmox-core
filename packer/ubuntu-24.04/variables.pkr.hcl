# Proxmox Connection
variable "proxmox_api_url" {
  type        = string
  description = "Proxmox API URL"
}

variable "proxmox_api_token_id" {
  type        = string
  description = "Proxmox API Token ID"
}

variable "proxmox_api_token_secret" {
  type        = string
  sensitive   = true
  description = "Proxmox API Token Secret"
}

variable "proxmox_node" {
  type        = string
  description = "Proxmox node name"
}

variable "proxmox_storage_pool" {
  type        = string
  default     = "local-lvm"
  description = "Storage pool for VM disk"
}

variable "proxmox_iso_storage_pool" {
  type        = string
  default     = "local"
  description = "Storage pool for ISO files"
}

# VM Configuration
variable "vm_id" {
  type        = number
  default     = 9000
  description = "VM template ID"
}

variable "vm_name" {
  type        = string
  default     = "ubuntu-24.04-docker-template"
  description = "VM template name"
}

variable "vm_description" {
  type        = string
  default     = "Ubuntu 24.04 LVM template with Docker"
  description = "VM template description"
}

variable "disk_size" {
  type        = string
  default     = "32G"
  description = "Disk size"
}

variable "vm_cpu_cores" {
  type        = number
  default     = 2
  description = "Number of CPU cores"
}

variable "vm_cpu_sockets" {
  type        = number
  default     = 1
  description = "Number of CPU sockets"
}

variable "vm_cpu_type" {
  type        = string
  default     = "host"
  description = "CPU type"
}

variable "vm_memory" {
  type        = number
  default     = 2048
  description = "Memory in MB"
}

variable "network_bridge" {
  type        = string
  default     = "vmbr0"
  description = "Network bridge"
}

# Ubuntu ISO
variable "iso_file" {
  type        = string
  default     = "local:iso/ubuntu-24.04.1-live-server-amd64.iso"
  description = "Ubuntu ISO local file"
}

# Cloud-init Configuration
variable "username" {
  type        = string
  default     = "ubuntu"
  description = "Default user username"
}

variable "password" {
  type        = string
  sensitive   = true
  description = "Default user password hash. 'mkpasswd -m sha-512 ubuntu'"
}

variable "hostname" {
  type        = string
  default     = "ubuntu-template"
  description = "System hostname"
}

variable "domain" {
  type        = string
  default     = "local"
  description = "System domain"
}

variable "timezone" {
  type        = string
  default     = "Europe/Lisbon"
  description = "System timezone"
}

variable "locale" {
  type        = string
  default     = "en_US.UTF-8"
  description = "System locale"
}

variable "keyboard_layout" {
  type        = string
  default     = "us"
  description = "Keyboard layout"
}

variable "keyboard_variant" {
  type        = string
  default     = "intl"
  description = "Keyboard variant"
}

# Packages
variable "packages" {
  type        = list(string)
  description = "List of packages to install"
  default = [
    "qemu-guest-agent",
    "cloud-init",
    "lvm2",
    "vim",
    "curl",
    "wget",
    "htop",
    "net-tools",
    "git",
    "build-essential",
    "ca-certificates",
    "gnupg",
    "lsb-release",
    "software-properties-common",
    "apt-transport-https"
  ]
}

# SSH Configuration
variable "ssh_username" {
  type        = string
  default     = "ubuntu"
  description = "SSH username for Packer"
}

variable "ssh_private_key_file" {
  type        = string
  description = "Private key file to use for SSH."
  sensitive   = true
  default     = "~/.ssh/id_ed25519"
}

variable "ssh_timeout" {
  type        = string
  default     = "20m"
  description = "SSH timeout"
}

# Additional Users (optional)
variable "additional_users" {
  type = list(object({
    name                = string
    groups              = list(string)
    sudo                = string
    ssh_authorized_keys = list(string)
    lock_passwd         = bool
  }))
  default     = []
  description = "Additional users to create"
}

variable "ssh_authorized_keys" {
  type        = list(string)
  default     = []
  description = "SSH authorized keys for default user"
}

variable "tags" {
  type        = string
  description = "The tags to set. This is a semicolon separated list. For example, debian-12;template."
  default     = "packer;ubuntu"
}

# NTP Servers
variable "ntp_servers" {
  type        = list(string)
  description = "List of NTP servers"
  default = [
    "0.pool.ntp.org",
    "1.pool.ntp.org",
    "2.pool.ntp.org",
    "3.pool.ntp.org"
  ]
}

# HTTP Proxy
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

# Grafana Alloy
variable "grafana_alloy_version" {
  type    = string
  default = "1.11.3"
}
