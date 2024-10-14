# Create LXC Container

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
| [proxmox_lxc.dns](https://registry.terraform.io/providers/Telmate/proxmox/3.0.1-rc4/docs/resources/lxc) | resource |
| [random_pet.dns](https://registry.terraform.io/providers/hashicorp/random/3.6.3/docs/resources/pet) | resource |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_cores"></a> [cores](#input\_cores) | The number of cores assigned to the container. | `number` | `2` | no |
| <a name="input_cpulimit"></a> [cpulimit](#input\_cpulimit) | A number to limit CPU usage by. Default is 0. | `number` | `0` | no |
| <a name="input_hostname"></a> [hostname](#input\_hostname) | Specifies the host name of the container. | `string` | `"dns1"` | no |
| <a name="input_memory"></a> [memory](#input\_memory) | A number containing the amount of RAM to assign to the container (in MB). | `number` | `512` | no |
| <a name="input_nameserver"></a> [nameserver](#input\_nameserver) | The DNS server IP address used by the container. | `string` | n/a | yes |
| <a name="input_network_bridge"></a> [network\_bridge](#input\_network\_bridge) | The bridge to attach the network interface to. | `string` | `"vmbr0"` | no |
| <a name="input_network_fw"></a> [network\_fw](#input\_network\_fw) | A boolean to enable the firewall on the network interface. | `bool` | `true` | no |
| <a name="input_network_gw"></a> [network\_gw](#input\_network\_gw) | The IPv4 address belonging to the network interface's default gateway. | `string` | n/a | yes |
| <a name="input_network_ip_cidr"></a> [network\_ip\_cidr](#input\_network\_ip\_cidr) | The IPv4 address of the network interface. Can be a static IPv4 address (in CIDR notation), "dhcp", or "manual". | `string` | n/a | yes |
| <a name="input_network_name"></a> [network\_name](#input\_network\_name) | The name of the network interface as seen from inside the container | `string` | `"eth0"` | no |
| <a name="input_onboot"></a> [onboot](#input\_onboot) | A boolean that determines if the container will start on boot. | `bool` | `true` | no |
| <a name="input_ostemplate"></a> [ostemplate](#input\_ostemplate) | The volume identifier that points to the OS template or backup file. | `string` | `"local:vztmpl/ubuntu-24.04-standard_24.04-2_amd64.tar.zst"` | no |
| <a name="input_password"></a> [password](#input\_password) | Sets the root password inside the container. | `string` | n/a | yes |
| <a name="input_rootfs_size"></a> [rootfs\_size](#input\_rootfs\_size) | Size of the underlying volume. Must end in T, G, M, or K. | `string` | `"8G"` | no |
| <a name="input_rootfs_storage"></a> [rootfs\_storage](#input\_rootfs\_storage) | A string containing the volume , directory, or device to be mounted into the container (at the path specified by mp). | `string` | `"local-lvm"` | no |
| <a name="input_searchdomain"></a> [searchdomain](#input\_searchdomain) | Sets the DNS search domains for the container. | `string` | n/a | yes |
| <a name="input_ssh_public_keys"></a> [ssh\_public\_keys](#input\_ssh\_public\_keys) | Multi-line string of SSH public keys that will be added to the container. Can be defined using heredoc syntax. | `string` | n/a | yes |
| <a name="input_start"></a> [start](#input\_start) | valueA boolean that determines if the container is started after creation. | `bool` | `true` | no |
| <a name="input_swap"></a> [swap](#input\_swap) | A number that sets the amount of swap memory available to the container. | `number` | `512` | no |
| <a name="input_tags"></a> [tags](#input\_tags) | Tags of the container, semicolon-delimited (e.g. "terraform;test"). This is only meta information. | `string` | `"terraform"` | no |
| <a name="input_target_node"></a> [target\_node](#input\_target\_node) | A string containing the cluster node name. | `string` | `"pve1"` | no |
| <a name="input_unprivileged"></a> [unprivileged](#input\_unprivileged) | A boolean that makes the container run as an unprivileged user. | `bool` | `true` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_hostname"></a> [hostname](#output\_hostname) | n/a |
| <a name="output_ip"></a> [ip](#output\_ip) | n/a |
<!-- END_TF_DOCS -->
