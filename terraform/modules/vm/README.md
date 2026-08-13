# vm

Clone one VM from the Packer template, with static-IP cloud-init. Generic —
takes no workload-specific inputs.

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
| ---- | ------- |
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | > 1.9.0, < 2.0 |
| <a name="requirement_proxmox"></a> [proxmox](#requirement\_proxmox) | ~> 0.85 |

## Providers

| Name | Version |
| ---- | ------- |
| <a name="provider_proxmox"></a> [proxmox](#provider\_proxmox) | 0.111.1 |

## Modules

No modules.

## Resources

| Name | Type |
| ---- | ---- |
| [proxmox_virtual_environment_vm.this](https://registry.terraform.io/providers/bpg/proxmox/latest/docs/resources/virtual_environment_vm) | resource |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_cipassword"></a> [cipassword](#input\_cipassword) | cloud-init password | `string` | n/a | yes |
| <a name="input_ciuser"></a> [ciuser](#input\_ciuser) | cloud-init username | `string` | `"ubuntu"` | no |
| <a name="input_cores"></a> [cores](#input\_cores) | vCPU cores | `number` | `2` | no |
| <a name="input_datastore_id"></a> [datastore\_id](#input\_datastore\_id) | Proxmox datastore for disk + cloud-init | `string` | `"local-lvm"` | no |
| <a name="input_description"></a> [description](#input\_description) | VM description / notes | `string` | `"Managed by Terraform (vm module)"` | no |
| <a name="input_disk"></a> [disk](#input\_disk) | Disk size in GB (>= template disk) | `number` | `60` | no |
| <a name="input_gateway"></a> [gateway](#input\_gateway) | Default gateway | `string` | n/a | yes |
| <a name="input_ip_cidr"></a> [ip\_cidr](#input\_ip\_cidr) | Static IPv4 in CIDR form, e.g. 192.168.68.30/22 | `string` | n/a | yes |
| <a name="input_memory"></a> [memory](#input\_memory) | Memory in MB | `number` | `8192` | no |
| <a name="input_name"></a> [name](#input\_name) | VM name | `string` | n/a | yes |
| <a name="input_nameserver"></a> [nameserver](#input\_nameserver) | DNS servers, in resolution order | `list(string)` | n/a | yes |
| <a name="input_network_bridge"></a> [network\_bridge](#input\_network\_bridge) | Network bridge | `string` | `"vmbr0"` | no |
| <a name="input_searchdomain"></a> [searchdomain](#input\_searchdomain) | DNS search domain | `string` | n/a | yes |
| <a name="input_sshkeys"></a> [sshkeys](#input\_sshkeys) | Newline-delimited SSH public keys | `string` | n/a | yes |
| <a name="input_tags"></a> [tags](#input\_tags) | Proxmox tags | `list(string)` | <pre>[<br/>  "terraform"<br/>]</pre> | no |
| <a name="input_target_node"></a> [target\_node](#input\_target\_node) | Proxmox node to place the VM on | `string` | n/a | yes |
| <a name="input_template_vmid"></a> [template\_vmid](#input\_template\_vmid) | VMID of the Packer template to clone from | `number` | n/a | yes |
| <a name="input_vmid"></a> [vmid](#input\_vmid) | VM ID in Proxmox | `number` | n/a | yes |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_ip"></a> [ip](#output\_ip) | Node IPv4 address |
| <a name="output_name"></a> [name](#output\_name) | VM name |
| <a name="output_vmid"></a> [vmid](#output\_vmid) | VM ID |
<!-- END_TF_DOCS -->
