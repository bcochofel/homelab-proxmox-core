output "server_name" {
  value = proxmox_vm_qemu.ci.name
}

output "server_ip" {
  value = proxmox_vm_qemu.ci.ipconfig0
}
