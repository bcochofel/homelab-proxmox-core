# --------------------------------------------------------
# Proxmox connection (bpg/proxmox)
# --------------------------------------------------------
variable "proxmox_endpoint" {
  type        = string
  description = "Proxmox API endpoint, e.g. https://192.168.68.20:8006/"
}

variable "proxmox_api_token" {
  type        = string
  description = "API token, form user@realm!tokenid=secret"
  sensitive   = true
}

variable "proxmox_insecure" {
  type        = bool
  description = "Skip TLS verification (homelab self-signed cert)"
  default     = true
}

variable "proxmox_ssh_username" {
  type        = string
  description = "SSH username for provider operations that require SSH"
  default     = "root"
}

variable "target_node" {
  type        = string
  description = "Proxmox node name to place VMs on"
  default     = "pve1"
}

variable "vm_template" {
  type        = string
  description = "Name of the Packer-built template to clone"
  default     = "ubuntu-26.04-core"
}

# --------------------------------------------------------
# Caddy VM
# --------------------------------------------------------
variable "caddy_node" {
  type = object({
    name    = string
    vmid    = optional(number) # omitted -> Proxmox auto-assigns the next available ID
    ip_cidr = string           # e.g. 192.168.68.16/22
    cores   = number
    memory  = number # MB
    disk    = number # GB
  })
  description = "Caddy reverse-proxy node definition"
  default = {
    name = "proxy", ip_cidr = "192.168.68.16/22", cores = 1, memory = 1024, disk = 50
  }
}

# --------------------------------------------------------
# DNS VM (CoreDNS + Pihole)
# --------------------------------------------------------
variable "dns_node" {
  type = object({
    name    = string
    vmid    = optional(number) # omitted -> Proxmox auto-assigns the next available ID
    ip_cidr = string           # e.g. 192.168.68.15/22 — the VM's own management IP;
    # CoreDNS (primary, 192.168.68.2) and Pihole (192.168.68.5) each get a
    # separate Docker macvlan IP, which is Docker-level config, not a
    # Terraform/Proxmox-level concern. A third CoreDNS instance (secondary,
    # 192.168.68.3, AXFR from the primary) runs on the user's QNAP NAS,
    # entirely outside this repo/Terraform's reach.
    cores  = number
    memory = number # MB
    disk   = number # GB
  })
  description = "CoreDNS + Pihole node definition (two Docker Compose services, one VM). Proxmox name/hostname is \"server01\" — the Ansible inventory group is still \"dns\" (hardcoded in templates/inventory.ini.tftpl), decoupled from this display name."
  default = {
    name = "server01", ip_cidr = "192.168.68.15/22", cores = 2, memory = 2048, disk = 50
  }
}

# --------------------------------------------------------
# Networking
# --------------------------------------------------------
variable "gateway" {
  type        = string
  description = "Network gateway"
  default     = "192.168.68.1"
}

variable "network_bridge" {
  type        = string
  description = "Proxmox network bridge"
  default     = "vmbr0"
}

variable "nameserver" {
  type        = list(string)
  description = "DNS servers for cloud-init, in resolution order — CoreDNS (primary, authoritative for the local zone) then Pihole (ad-blocking, conditionally forwards the local zone to CoreDNS) — the two Docker macvlan IPs on the dns VM. Used by every VM except dns itself — see dns_node_nameserver"
  default     = ["192.168.68.2", "192.168.68.5"]
}

variable "dns_node_nameserver" {
  type        = list(string)
  description = "DNS servers for cloud-init on the dns VM itself, in resolution order. Deliberately NOT the CoreDNS/Pihole macvlan IPs (192.168.68.2/.5): Docker's macvlan driver cannot be reached from its own Docker host by design (see CLAUDE.md), so the dns VM using its own not-yet-running containers as its OS resolver is unfixable, not just a bring-up ordering issue. Matches ansible/inventory/group_vars/dns.yml's dns_forward_resolvers"
  default     = ["1.1.1.1", "8.8.8.8"]
}

variable "searchdomain" {
  type        = string
  description = "DNS search domain"
  default     = "homelab.bcochofel.com"
}

# --------------------------------------------------------
# cloud-init
# --------------------------------------------------------
variable "ciuser" {
  type        = string
  description = "cloud-init user (matches Packer template default user)"
  default     = "ubuntu"
}

variable "cipassword" {
  type        = string
  description = "cloud-init user password"
  sensitive   = true
}

variable "sshkeys" {
  type        = string
  description = "Newline-delimited SSH public keys for the cloud-init user"
}

# --------------------------------------------------------
# Ansible inventory generation
# --------------------------------------------------------
variable "ansible_user" {
  type        = string
  description = "Remote user Ansible connects as (matches ansible.cfg)"
  default     = "ubuntu"
}
