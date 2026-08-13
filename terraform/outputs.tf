output "caddy" {
  value = {
    name = module.caddy.name
    vmid = module.caddy.vmid
    ip   = module.caddy.ip
  }
  description = "Caddy node details"
}

output "dns" {
  value = {
    name = module.dns.name
    vmid = module.dns.vmid
    ip   = module.dns.ip
  }
  description = "DNS node details (VM's own IP — CoreDNS/Pihole's macvlan IPs are Docker-level, not visible here)"
}

output "inventory_path" {
  value       = local_file.ansible_inventory.filename
  description = "Path to the generated Ansible inventory"
}
