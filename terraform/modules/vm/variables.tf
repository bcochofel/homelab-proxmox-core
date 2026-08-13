variable "name" {
  type        = string
  description = "VM name"
}

variable "vmid" {
  type        = number
  description = "VM ID in Proxmox"
}

variable "target_node" {
  type        = string
  description = "Proxmox node to place the VM on"
}

variable "template_vmid" {
  type        = number
  description = "VMID of the Packer template to clone from"
}

variable "description" {
  type        = string
  description = "VM description / notes"
  default     = "Managed by Terraform (vm module)"
}

variable "tags" {
  type        = list(string)
  description = "Proxmox tags"
  default     = ["terraform"]
}

variable "cores" {
  type        = number
  description = "vCPU cores"
  default     = 2
}

variable "memory" {
  type        = number
  description = "Memory in MB"
  default     = 8192
}

variable "disk" {
  type        = number
  description = "Disk size in GB (>= template disk)"
  default     = 60
}

variable "datastore_id" {
  type        = string
  description = "Proxmox datastore for disk + cloud-init"
  default     = "local-lvm"
}

variable "network_bridge" {
  type        = string
  description = "Network bridge"
  default     = "vmbr0"
}

variable "ip_cidr" {
  type        = string
  description = "Static IPv4 in CIDR form, e.g. 192.168.68.30/22"
}

variable "gateway" {
  type        = string
  description = "Default gateway"
}

variable "nameserver" {
  type        = list(string)
  description = "DNS servers, in resolution order"
}

variable "searchdomain" {
  type        = string
  description = "DNS search domain"
}

variable "ciuser" {
  type        = string
  description = "cloud-init username"
  default     = "ubuntu"
}

variable "cipassword" {
  type        = string
  description = "cloud-init password"
  sensitive   = true
}

variable "sshkeys" {
  type        = string
  description = "Newline-delimited SSH public keys"
}
