# --------------------------------------------------------
# Proxmox connection
# --------------------------------------------------------
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
  description = "Proxmox API Token Secret"
  sensitive   = true
}

variable "proxmox_node" {
  type        = string
  description = "Proxmox node name"
}

variable "proxmox_skip_tls_verify" {
  type        = bool
  description = "Skip TLS verification"
}

# --------------------------------------------------------
# ISO Boot configuration
# --------------------------------------------------------
variable "boot_iso_type" {
  type        = string
  description = "Boot ISO type"
  default     = "scsi"
}

variable "boot_iso_file" {
  type        = string
  description = "Ubuntu ISO local file"
  default     = "local:iso/ubuntu-26.04-live-server-amd64.iso"
}

variable "boot_iso_unmount" {
  type        = bool
  description = "Unmount ISO after installation?"
  default     = true
}

# --------------------------------------------------------
# Virtual Machine Settings
# --------------------------------------------------------
variable "vm_id" {
  type        = number
  description = "VM template ID"
  default     = 9001
}

variable "vm_name" {
  type        = string
  description = "VM template name"
  default     = "ubuntu-26.04-core"
}

variable "vm_description" {
  type        = string
  description = "VM template description"
  default     = "Ubuntu 26.04 LTS template (Docker, Caddy reverse-proxy host)"
}

variable "qemu_agent" {
  type    = bool
  default = true
}

variable "scsi_controller" {
  type    = string
  default = "virtio-scsi-single"
}

variable "disk_size" {
  type        = string
  description = "Disk size"
  default     = "50G"
}

variable "storage_pool" {
  type        = string
  description = "Storage pool for VM disk"
  default     = "local-lvm"
}

variable "disk_type" {
  type        = string
  description = "Disk Type"
  default     = "scsi"
}

variable "vm_cpu_cores" {
  type        = number
  description = "Number of CPU cores"
  default     = 1
}

variable "vm_cpu_sockets" {
  type        = number
  description = "Number of CPU sockets"
  default     = 1
}

variable "vm_cpu_type" {
  type        = string
  description = "CPU type"
  default     = "host"
}

variable "vm_memory" {
  type        = number
  description = "Memory in MB"
  default     = 2048
}

variable "network_model" {
  type        = string
  description = "Network Model"
  default     = "virtio"
}

variable "network_bridge" {
  type        = string
  description = "Network bridge"
  default     = "vmbr0"
}

# --------------------------------------------------------
# Cloud-init and autoinstall
# --------------------------------------------------------
variable "username" {
  type        = string
  description = "Default user"
  default     = "ubuntu"
}

variable "password_hash" {
  type        = string
  description = <<EOT
Default user password hashed. Use
$ mkpasswd -m sha-512 '<yourpassword>'
EOT
  sensitive   = true
}

variable "hostname" {
  type        = string
  description = "System hostname"
  default     = "ubuntu-core"
}

variable "timezone" {
  type        = string
  description = "System timezone"
  default     = "Europe/Lisbon"
}

variable "locale" {
  type        = string
  description = "System locale"
  default     = "en_US.UTF-8"
}

variable "keyboard_layout" {
  type        = string
  description = "Keyboard layout"
  default     = "us"
}

variable "keyboard_variant" {
  type        = string
  description = "Keyboard variant"
  default     = "intl"
}

# Packages
variable "packages" {
  type        = list(string)
  description = "List of packages to install"
  default = [
    "qemu-guest-agent",
    "cloud-init",
    "lvm2",
    # minimal OS
    "ubuntu-minimal",
    # docker dependencies
    "ca-certificates",
    "curl",
    "gnupg",
    "lsb-release",
    "apt-transport-https",
    "software-properties-common",
    # troubleshooting tools
    "whois",
    "net-tools",
    "inetutils-ping",
    "traceroute",
    "dnsutils",
    "iproute2",
    "tcpdump",
    "unzip",
    "jq",
    "htop",
    "tmux",
    "lsof",
    "strace",
    "vim-nox",
    "mc",
    "sysstat",
    "rsync",
    "git"
  ]
}

# SSH Configuration
variable "ssh_private_key_file" {
  type        = string
  description = "Private key file to use for SSH."
  sensitive   = true
}

variable "ssh_timeout" {
  type        = string
  description = "SSH timeout"
  default     = "20m"
}

# SSH Keys for Default user
variable "ssh_authorized_keys" {
  type        = list(string)
  description = "SSH authorized keys for default user"
  default     = []
}

# Additional Users (optional)
variable "additional_users" {
  type = list(object({
    name                = string
    groups              = list(string)
    sudo                = string
    shell               = string
    ssh_authorized_keys = list(string)
    lock_passwd         = bool
  }))
  description = "Additional users to create"
  default     = []
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

# Docker
variable "install_docker" {
  type        = bool
  description = "Wheter to install Docker"
  default     = true
}
