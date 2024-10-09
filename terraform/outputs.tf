output "server_name" {
  value       = module.dev_workstation.server_name
  description = "VM Server name."
}

output "server_ip" {
  value       = split("=", split("/", module.dev_workstation.server_ip)[0])[1]
  description = "VM Server IP."
}
