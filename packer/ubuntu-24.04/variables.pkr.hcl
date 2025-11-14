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
  default     = "local:iso/ubuntu-24.04.3-live-server-amd64.iso"
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
  default     = 9000
}

variable "vm_name" {
  type        = string
  description = "VM template name"
  default     = "ubuntu-24.04-template"
}

variable "vm_description" {
  type        = string
  description = "VM template description"
  default     = "Ubuntu 24.04 LTS template"
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
  default     = "60G"
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
  default     = 2
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

variable "password" {
  type        = string
  description = "Default user password"
  sensitive   = true
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
  default     = "ubuntu-template"
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
    "vim",
    "curl",
    "wget",
    "mc",
    "sysstat",
    "logwatch",
    "htop",
    "net-tools",
    "rsync",
    "lsof",
    "git",
    "ca-certificates",
    "gnupg",
    "lsb-release",
    "sosreport",
    "xfsprogs",
    "unattended-upgrades",
    "apt-listchanges",
    "needrestart",
    "aide",
    "auditd",
    "audispd-plugins",
    "rkhunter",
    "lynis",
    "python3-pip",
    "python3-venv",
    "jq"
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

# HTTP Proxy
variable "enable_proxy" {
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
  type        = string
  description = "Grafana Alloy version to install"
  default     = "1.11.3"
}
