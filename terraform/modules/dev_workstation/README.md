# Clone VM

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
|------|---------|
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | ~> 1.9.0 |
| <a name="requirement_proxmox"></a> [proxmox](#requirement\_proxmox) | 3.0.1-rc4 |
| <a name="requirement_random"></a> [random](#requirement\_random) | 3.6.3 |

## Providers

| Name | Version |
|------|---------|
| <a name="provider_proxmox"></a> [proxmox](#provider\_proxmox) | 3.0.1-rc4 |
| <a name="provider_random"></a> [random](#provider\_random) | 3.6.3 |

## Modules

No modules.

## Resources

| Name | Type |
|------|------|
| [proxmox_vm_qemu.ci](https://registry.terraform.io/providers/Telmate/proxmox/3.0.1-rc4/docs/resources/vm_qemu) | resource |
| [random_pet.vm_name](https://registry.terraform.io/providers/hashicorp/random/3.6.3/docs/resources/pet) | resource |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_agent"></a> [agent](#input\_agent) | Set to 1 to enable the QEMU Guest Agent.<br>Note, you must run the qemu-guest-agent daemon in the guest for this to have any effect. | `number` | `1` | no |
| <a name="input_boot_order"></a> [boot\_order](#input\_boot\_order) | The boot order for the VM. For example: "order=scsi0;ide2;net0". | `string` | `"order=scsi0"` | no |
| <a name="input_cores"></a> [cores](#input\_cores) | valueThe number of CPU cores per CPU socket to allocate to the VM. | `number` | `1` | no |
| <a name="input_full_clone"></a> [full\_clone](#input\_full\_clone) | Set to true to create a full clone, or false to create a linked clone. | `bool` | `true` | no |
| <a name="input_gateway"></a> [gateway](#input\_gateway) | Network Gatework for first IP address to assign to guest. | `string` | n/a | yes |
| <a name="input_ip_cidr"></a> [ip\_cidr](#input\_ip\_cidr) | Network CIDR for first network interface. Can also be 'dhcp' | `string` | n/a | yes |
| <a name="input_memory"></a> [memory](#input\_memory) | The amount of memory to allocate to the VM in Megabytes. | `number` | `512` | no |
| <a name="input_network_bridge"></a> [network\_bridge](#input\_network\_bridge) | Bridge to which the network device should be attached. | `string` | `"vmbr0"` | no |
| <a name="input_network_model"></a> [network\_model](#input\_network\_model) | Network Card Model. The virtio model provides the best performance with very low CPU overhead.<br>If your guest does not support this driver, it is usually best to use e1000. | `string` | `"virtio"` | no |
| <a name="input_onboot"></a> [onboot](#input\_onboot) | Whether to have the VM startup after the PVE node starts. | `bool` | `true` | no |
| <a name="input_os_type"></a> [os\_type](#input\_os\_type) | Which provisioning method to use, based on the OS type. | `string` | `"cloud-init"` | no |
| <a name="input_scsihw"></a> [scsihw](#input\_scsihw) | The SCSI controller to emulate. | `string` | `"virtio-scsi-pci"` | no |
| <a name="input_sockets"></a> [sockets](#input\_sockets) | valueThe number of CPU sockets to allocate to the VM. | `number` | `1` | no |
| <a name="input_tags"></a> [tags](#input\_tags) | Tags of the VM. Comma-separated values (e.g. tag1,tag2,tag3). | `string` | `"terraform"` | no |
| <a name="input_target_node"></a> [target\_node](#input\_target\_node) | The name of the Proxmox Node on which to place the VM. | `string` | `"pve1"` | no |
| <a name="input_vm_desc"></a> [vm\_desc](#input\_vm\_desc) | The description of the VM. Shows as the 'Notes' field in the Proxmox GUI. | `string` | `"VM created by Terraform."` | no |
| <a name="input_vm_id"></a> [vm\_id](#input\_vm\_id) | The ID of the VM in Proxmox.<br>The default value of 0 indicates it should use the next available ID in the sequence. | `number` | `0` | no |
| <a name="input_vm_name"></a> [vm\_name](#input\_vm\_name) | The name of the VM within Proxmox.<br>If not set will be generated by random\_pet | `string` | `""` | no |
| <a name="input_vm_template"></a> [vm\_template](#input\_vm\_template) | The base VM from which to clone to create the new VM. | `string` | n/a | yes |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_server_ip"></a> [server\_ip](#output\_server\_ip) | n/a |
| <a name="output_server_name"></a> [server\_name](#output\_server\_name) | n/a |
<!-- END_TF_DOCS -->