output "name" {
  value       = proxmox_virtual_environment_vm.this.name
  description = "VM name"
}

output "vmid" {
  value       = proxmox_virtual_environment_vm.this.vm_id
  description = "VM ID"
}

output "ip" {
  # Strip CIDR suffix from the configured static IP — authoritative and avoids
  # waiting on the guest agent for inventory generation.
  value       = split("/", var.ip_cidr)[0]
  description = "Node IPv4 address"
}
