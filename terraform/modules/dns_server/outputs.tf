output "hostname" {
  value = proxmox_lxc.dns.hostname
}

output "ip" {
  value = proxmox_lxc.dns.network[0].ip
}
