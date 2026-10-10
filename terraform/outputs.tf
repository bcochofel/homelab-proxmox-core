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

output "runner01" {
  value = {
    name = module.runner01.name
    vmid = module.runner01.vmid
    ip   = module.runner01.ip
  }
  description = "GitHub Actions runner node details (Ansible inventory group \"github_runner\")"
}

# The same inventory, for the CI dry-run runner: its checkout has no
# hosts.ini (gitignored), so `mise run ansible:check` writes it from this
# output with the plan credentials (docs/SETUP.md). Sensitive only to keep
# the LAN addresses out of plan output and CI logs.
output "ansible_inventory" {
  value       = local.ansible_inventory
  description = "Rendered Ansible inventory (hosts.ini), read by mise run ansible:check"
  sensitive   = true
}

output "inventory_path" {
  value       = local_file.ansible_inventory.filename
  description = "Path to the generated Ansible inventory"
}
