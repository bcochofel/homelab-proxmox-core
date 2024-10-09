# Terraform for Proxmox

Deploy core infrastructure components on Proxmox homelab server.

## Proxmox Setup

Create ```terraform``` group, user and set permissions

```bash
pveum role add TerraformProv -privs "Datastore.AllocateSpace Datastore.AllocateTemplate Datastore.Audit Pool.Allocate Sys.Audit Sys.Console Sys.Modify VM.Allocate VM.Audit VM.Clone VM.Config.CDROM VM.Config.Cloudinit VM.Config.CPU VM.Config.Disk VM.Config.HWType VM.Config.Memory VM.Config.Network VM.Config.Options VM.Migrate VM.Monitor VM.PowerMgmt SDN.Use"
pveum user add terraform@pve --password <password>
pveum aclmod / -user terraform@pve -role TerraformProv
```

Create API Token

```bash
pveum user token add terraform@pve terraform-automation --privsep 0
```

**Note:** The above command will output the values you need to use in to authenticate

## Terraform Configuration

This repository uses HCP Terraform to store the state file.

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
|------|---------|
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | ~> 1.9.0 |
| <a name="requirement_proxmox"></a> [proxmox](#requirement\_proxmox) | 3.0.1-rc4 |
| <a name="requirement_random"></a> [random](#requirement\_random) | 3.6.3 |

## Providers

No providers.

## Modules

| Name | Source | Version |
|------|--------|---------|
| <a name="module_dev_workstation"></a> [dev\_workstation](#module\_dev\_workstation) | ./modules/dev_workstation | n/a |

## Resources

No resources.

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_pm_api_token_id"></a> [pm\_api\_token\_id](#input\_pm\_api\_token\_id) | This is an API token you have previously created for a specific user. | `string` | n/a | yes |
| <a name="input_pm_api_token_secret"></a> [pm\_api\_token\_secret](#input\_pm\_api\_token\_secret) | This uuid is only available when the token was initially created. | `string` | n/a | yes |
| <a name="input_pm_api_url"></a> [pm\_api\_url](#input\_pm\_api\_url) | This is the target Proxmox API endpoint. | `string` | n/a | yes |

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