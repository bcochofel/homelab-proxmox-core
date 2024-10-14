output "workstation_hostname" {
  value       = module.dev_workstation.server_name
  description = "Developer Workstation hostname."
}

output "workstation_ip" {
  value       = split("=", split("/", module.dev_workstation.server_ip)[0])[1]
  description = "Developer Workstation IP."
}

output "dns_hostname" {
  value       = module.dns_server.hostname
  description = "DNS Server hostname."
}

output "dns_ip" {
  value       = split("/", module.dns_server.ip)[0]
  description = "DNS Server IP"
}
