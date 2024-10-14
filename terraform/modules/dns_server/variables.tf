variable "target_node" {
  type        = string
  description = <<EOT
A string containing the cluster node name.
EOT
  default     = "pve1"
}

variable "hostname" {
  type        = string
  description = "Specifies the host name of the container."
  default     = "dns1"
}

variable "ostemplate" {
  type        = string
  description = "The volume identifier that points to the OS template or backup file."
  default     = "local:vztmpl/ubuntu-24.04-standard_24.04-2_amd64.tar.zst"
}

variable "password" {
  type        = string
  description = "Sets the root password inside the container."
}

variable "unprivileged" {
  type        = bool
  description = "A boolean that makes the container run as an unprivileged user."
  default     = true
}

variable "cores" {
  type        = number
  description = "The number of cores assigned to the container."
  default     = 2
}

variable "cpulimit" {
  type        = number
  description = "A number to limit CPU usage by. Default is 0."
  default     = 0
}

variable "memory" {
  type        = number
  description = "A number containing the amount of RAM to assign to the container (in MB)."
  default     = 512
}

variable "swap" {
  type        = number
  description = "A number that sets the amount of swap memory available to the container."
  default     = 512
}

variable "rootfs_storage" {
  type        = string
  description = <<EOT
A string containing the volume , directory, or device to be mounted into the container (at the path specified by mp).
EOT
  default     = "local-lvm"
}

variable "rootfs_size" {
  type        = string
  description = "Size of the underlying volume. Must end in T, G, M, or K."
  default     = "8G"
}

variable "network_name" {
  type        = string
  description = "The name of the network interface as seen from inside the container"
  default     = "eth0"
}

variable "network_bridge" {
  type        = string
  description = "The bridge to attach the network interface to."
  default     = "vmbr0"
}

variable "network_ip_cidr" {
  type        = string
  description = <<EOT
The IPv4 address of the network interface. Can be a static IPv4 address (in CIDR notation), "dhcp", or "manual".
EOT
}

variable "network_gw" {
  type        = string
  description = "The IPv4 address belonging to the network interface's default gateway."
}

variable "network_fw" {
  type        = bool
  description = "A boolean to enable the firewall on the network interface."
  default     = true
}

variable "onboot" {
  type        = bool
  description = "A boolean that determines if the container will start on boot."
  default     = true
}

variable "start" {
  type        = bool
  description = "valueA boolean that determines if the container is started after creation."
  default     = true
}

variable "ssh_public_keys" {
  type        = string
  description = <<EOT
Multi-line string of SSH public keys that will be added to the container. Can be defined using heredoc syntax.
EOT
}

variable "tags" {
  type        = string
  description = <<EOT
Tags of the container, semicolon-delimited (e.g. "terraform;test"). This is only meta information.
EOT
  default     = "terraform"
}

variable "nameserver" {
  type        = string
  description = "The DNS server IP address used by the container."
}

variable "searchdomain" {
  type        = string
  description = "Sets the DNS search domains for the container."
}
