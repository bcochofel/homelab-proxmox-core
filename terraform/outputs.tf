output "workstation_hostname" {
  value       = one(module.dev_workstation[*].server_name)
  description = "Developer Workstation hostname if enabled."
}

output "workstation_ip" {
  value       = var.workstation_enabled == true ? split("=", split("/", one(module.dev_workstation[*].server_ip))[0])[1] : null
  description = "Developer Workstation IP if enabled."
}

output "dns_hostname" {
  value       = one(module.dns_server[*].hostname)
  description = "DNS Server hostname if enabled."
}

output "dns_ip" {
  value       = var.bind9_enabled == true ? split("/", one(module.dns_server[*].ip))[0] : null
  description = "DNS Server IP if enabled"
}
