# Terraform for Proxmox

Deploy core infrastructure components on Proxmox homelab server.

## Terraform Configuration

This repository uses HCP Terraform to store the state file.

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
|------|---------|
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | ~> 1.9.0 |
| <a name="requirement_local"></a> [local](#requirement\_local) | 2.5.2 |
| <a name="requirement_proxmox"></a> [proxmox](#requirement\_proxmox) | 3.0.1-rc4 |
| <a name="requirement_random"></a> [random](#requirement\_random) | 3.6.3 |

## Providers

| Name | Version |
|------|---------|
| <a name="provider_local"></a> [local](#provider\_local) | 2.5.2 |

## Modules

| Name | Source | Version |
|------|--------|---------|
| <a name="module_dev_workstation"></a> [dev\_workstation](#module\_dev\_workstation) | ./modules/dev_workstation | n/a |
| <a name="module_dns_server"></a> [dns\_server](#module\_dns\_server) | ./modules/dns_server | n/a |

## Resources

| Name | Type |
|------|------|
| [local_file.ansible_inventory](https://registry.terraform.io/providers/hashicorp/local/2.5.2/docs/resources/file) | resource |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_dns_hostname"></a> [dns\_hostname](#input\_dns\_hostname) | DNS Server hostname | `string` | `"dns1"` | no |
| <a name="input_dns_ip"></a> [dns\_ip](#input\_dns\_ip) | The DNS server IP address used by the container. | `string` | `"192.168.68.2"` | no |
| <a name="input_dns_root_password"></a> [dns\_root\_password](#input\_dns\_root\_password) | LXC root password for DNS server. | `string` | n/a | yes |
| <a name="input_gateway"></a> [gateway](#input\_gateway) | Network Gateway | `string` | `"192.168.68.1"` | no |
| <a name="input_nameserver"></a> [nameserver](#input\_nameserver) | Nameserver to use | `string` | `"8.8.8.8"` | no |
| <a name="input_network"></a> [network](#input\_network) | Network CIDR | `string` | n/a | yes |
| <a name="input_pm_api_token_id"></a> [pm\_api\_token\_id](#input\_pm\_api\_token\_id) | This is an API token you have previously created for a specific user. | `string` | n/a | yes |
| <a name="input_pm_api_token_secret"></a> [pm\_api\_token\_secret](#input\_pm\_api\_token\_secret) | This uuid is only available when the token was initially created. | `string` | n/a | yes |
| <a name="input_pm_api_url"></a> [pm\_api\_url](#input\_pm\_api\_url) | This is the target Proxmox API endpoint. | `string` | n/a | yes |
| <a name="input_searchdomain"></a> [searchdomain](#input\_searchdomain) | Sets the DNS search domains for the container. | `string` | n/a | yes |
| <a name="input_ssh_pubkeys"></a> [ssh\_pubkeys](#input\_ssh\_pubkeys) | SSH public keys for connecting to LXC container. | `string` | `"ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIEZGQwHOs8V9ndmLn3NuQXxuD0Ht4zaz+c6/WaEMAA6S bcochofel@NUC12WSHi7"` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_server_ip"></a> [server\_ip](#output\_server\_ip) | VM Server IP. |
| <a name="output_server_name"></a> [server\_name](#output\_server\_name) | VM Server name. |
<!-- END_TF_DOCS -->

## References

- [Proxmox Provider](https://registry.terraform.io/providers/Telmate/proxmox/latest/docs)
- [Random Provider](https://registry.terraform.io/providers/hashicorp/random/latest/docs)
- [HCP Terraform](https://app.terraform.io)
- [terraform_data Resource](https://developer.hashicorp.com/terraform/language/resources/terraform-data)
- [lifecycle Meta-Argument](https://developer.hashicorp.com/terraform/language/meta-arguments/lifecycle)
- [file Provisioner](https://developer.hashicorp.com/terraform/language/resources/provisioners/file)
- [remote-exec Provisioner](https://developer.hashicorp.com/terraform/language/resources/provisioners/remote-exec)
- [Setup BIND Server on Ubuntun 24.04](https://www.linuxbuzz.com/setup-bind-server-on-ubuntu/)
