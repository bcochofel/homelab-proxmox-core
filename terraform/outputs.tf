output "caddy" {
  value = {
    name = module.caddy.name
    vmid = module.caddy.vmid
    ip   = module.caddy.ip
  }
  description = "Caddy node details"
}

output "server01" {
  value = {
    name = module.server01.name
    vmid = module.server01.vmid
    ip   = module.server01.ip
  }
  description = "DNS node details (VM's own IP — CoreDNS/Pihole's macvlan IPs are Docker-level, not visible here). Ansible inventory group stays \"dns\" regardless (hardcoded in templates/inventory.ini.tftpl) — see CLAUDE.md."
}

output "inventory_path" {
  value       = local_file.ansible_inventory.filename
  description = "Path to the generated Ansible inventory"
}
