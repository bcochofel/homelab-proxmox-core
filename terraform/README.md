# Terraform

See [`../docs/TERRAFORM.md`](../docs/TERRAFORM.md).

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
| ---- | ------- |
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | > 1.9.0, < 2.0 |
| <a name="requirement_local"></a> [local](#requirement\_local) | 2.9.0 |
| <a name="requirement_proxmox"></a> [proxmox](#requirement\_proxmox) | ~> 0.85 |

## Providers

| Name | Version |
| ---- | ------- |
| <a name="provider_local"></a> [local](#provider\_local) | 2.9.0 |
| <a name="provider_proxmox"></a> [proxmox](#provider\_proxmox) | 0.111.1 |

## Modules

| Name | Source | Version |
| ---- | ------ | ------- |
| <a name="module_caddy"></a> [caddy](#module\_caddy) | ./modules/vm | n/a |
| <a name="module_dns"></a> [dns](#module\_dns) | ./modules/vm | n/a |

## Resources

| Name | Type |
| ---- | ---- |
| [local_file.ansible_inventory](https://registry.terraform.io/providers/hashicorp/local/2.9.0/docs/resources/file) | resource |
| [proxmox_virtual_environment_vms.template](https://registry.terraform.io/providers/bpg/proxmox/latest/docs/data-sources/virtual_environment_vms) | data source |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_ansible_user"></a> [ansible\_user](#input\_ansible\_user) | Remote user Ansible connects as (matches ansible.cfg) | `string` | `"ubuntu"` | no |
| <a name="input_caddy_node"></a> [caddy\_node](#input\_caddy\_node) | Caddy reverse-proxy node definition | <pre>object({<br/>    name    = string<br/>    vmid    = number<br/>    ip_cidr = string # e.g. 192.168.68.40/22<br/>    cores   = number<br/>    memory  = number # MB<br/>    disk    = number # GB<br/>  })</pre> | <pre>{<br/>  "cores": 1,<br/>  "disk": 50,<br/>  "ip_cidr": "192.168.68.40/22",<br/>  "memory": 1024,<br/>  "name": "proxy",<br/>  "vmid": 9540<br/>}</pre> | no |
| <a name="input_cipassword"></a> [cipassword](#input\_cipassword) | cloud-init user password | `string` | n/a | yes |
| <a name="input_ciuser"></a> [ciuser](#input\_ciuser) | cloud-init user (matches Packer template default user) | `string` | `"ubuntu"` | no |
| <a name="input_dns_node"></a> [dns\_node](#input\_dns\_node) | CoreDNS + Pihole node definition (two Docker Compose services, one VM) | <pre>object({<br/>    name    = string<br/>    vmid    = number<br/>    ip_cidr = string # e.g. 192.168.68.41/22 — the VM's own management IP;<br/>    # CoreDNS/Pihole each get a separate Docker macvlan IP (192.168.68.42/.43),<br/>    # which is Docker-level config, not a Terraform/Proxmox-level concern.<br/>    cores  = number<br/>    memory = number # MB<br/>    disk   = number # GB<br/>  })</pre> | <pre>{<br/>  "cores": 2,<br/>  "disk": 50,<br/>  "ip_cidr": "192.168.68.41/22",<br/>  "memory": 2048,<br/>  "name": "dns",<br/>  "vmid": 9541<br/>}</pre> | no |
| <a name="input_dns_node_nameserver"></a> [dns\_node\_nameserver](#input\_dns\_node\_nameserver) | DNS servers for cloud-init on the dns VM itself, in resolution order. Deliberately NOT the CoreDNS/Pihole macvlan IPs (192.168.68.42/.43): Docker's macvlan driver cannot be reached from its own Docker host by design (see CLAUDE.md), so the dns VM using its own not-yet-running containers as its OS resolver is unfixable, not just a bring-up ordering issue. Matches ansible/inventory/group\_vars/dns.yml's dns\_forward\_resolvers | `list(string)` | <pre>[<br/>  "1.1.1.1",<br/>  "8.8.8.8"<br/>]</pre> | no |
| <a name="input_gateway"></a> [gateway](#input\_gateway) | Network gateway | `string` | `"192.168.68.1"` | no |
| <a name="input_nameserver"></a> [nameserver](#input\_nameserver) | DNS servers for cloud-init, in resolution order — CoreDNS (ns1) then Pihole (ns2), the two Docker macvlan IPs on the dns VM (resolves hosts.local), not the QNAP-hosted ones being retired. Used by every VM except dns itself — see dns\_node\_nameserver | `list(string)` | <pre>[<br/>  "192.168.68.42",<br/>  "192.168.68.43"<br/>]</pre> | no |
| <a name="input_network_bridge"></a> [network\_bridge](#input\_network\_bridge) | Proxmox network bridge | `string` | `"vmbr0"` | no |
| <a name="input_proxmox_api_token"></a> [proxmox\_api\_token](#input\_proxmox\_api\_token) | API token, form user@realm!tokenid=secret | `string` | n/a | yes |
| <a name="input_proxmox_endpoint"></a> [proxmox\_endpoint](#input\_proxmox\_endpoint) | Proxmox API endpoint, e.g. https://192.168.68.20:8006/ | `string` | n/a | yes |
| <a name="input_proxmox_insecure"></a> [proxmox\_insecure](#input\_proxmox\_insecure) | Skip TLS verification (homelab self-signed cert) | `bool` | `true` | no |
| <a name="input_proxmox_ssh_username"></a> [proxmox\_ssh\_username](#input\_proxmox\_ssh\_username) | SSH username for provider operations that require SSH | `string` | `"root"` | no |
| <a name="input_searchdomain"></a> [searchdomain](#input\_searchdomain) | DNS search domain | `string` | `"homelab.bcochofel.com"` | no |
| <a name="input_sshkeys"></a> [sshkeys](#input\_sshkeys) | Newline-delimited SSH public keys for the cloud-init user | `string` | n/a | yes |
| <a name="input_target_node"></a> [target\_node](#input\_target\_node) | Proxmox node name to place VMs on | `string` | `"pve1"` | no |
| <a name="input_vm_template"></a> [vm\_template](#input\_vm\_template) | Name of the Packer-built template to clone | `string` | `"ubuntu-26.04-core"` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_caddy"></a> [caddy](#output\_caddy) | Caddy node details |
| <a name="output_dns"></a> [dns](#output\_dns) | DNS node details (VM's own IP — CoreDNS/Pihole's macvlan IPs are Docker-level, not visible here) |
| <a name="output_inventory_path"></a> [inventory\_path](#output\_inventory\_path) | Path to the generated Ansible inventory |
<!-- END_TF_DOCS -->
