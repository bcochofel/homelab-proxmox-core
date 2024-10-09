# homelab-proxmox-core

Homelab Core Components for Proxmox

## Bootstrapping new cluster

### Create Packer User for Proxmox

```bash
# create role and set privileges
pveum role add PackerProv -privs  "Pool.Audit Datastore.AllocateSpace Datastore.Allocate Datastore.Audit VM.Allocate VM.Audit VM.Backup VM.Clone VM.Config.CDROM VM.Config.CPU VM.Config.Cloudinit VM.Config.Disk VM.Config.HWType VM.Config.Memory VM.Config.Network VM.Config.Options VM.Console VM.Migrate VM.Monitor VM.PowerMgmt VM.Snapshot VM.Snapshot.Rollback SDN.Use"

# create user
pveum user add packer@pve --password Pack3rPr0v1s10n1ng

# set permissions
pveum aclmod / -user packer@pve -role PackerProv

# create API token
# this command outputs values needed for authentication
pveum user token add packer@pve packer-automation --privsep 0
```

### Create ```packer/ubuntu-server/secrets.auto.pkvars.hcl``` file

Create the secrets file with values from the last command

```hcl
pm_api_url = "<your proxmox api url>"
pm_api_token_id = "<your proxmox user>"
pm_api_token_secret = "<proxmox user api token>"
```

### Packer validate and build

Change the values of the variables ```ssh_username``` and ```ssh_private_key_file``` in the ```packer/ubuntu-server/variables.pkr.hcl``` file.

```bash
cd packer
packer init
packer validate ubuntu-server/
packer build ubuntu-server/
```

### Create Terraform User for Proxmox

```bash
# create role and set privileges
pveum role add TerraformProv -privs "Datastore.AllocateSpace Datastore.AllocateTemplate Datastore.Audit Pool.Allocate Sys.Audit Sys.Console Sys.Modify VM.Allocate VM.Audit VM.Clone VM.Config.CDROM VM.Config.Cloudinit VM.Config.CPU VM.Config.Disk VM.Config.HWType VM.Config.Memory VM.Config.Network VM.Config.Options VM.Migrate VM.Monitor VM.PowerMgmt SDN.Use"

# create user (set <password> to a password of your choice)
pveum user add terraform@pve --password <password>

# set permissions
pveum aclmod / -user terraform@pve -role TerraformProv

# create API token
# this command outputs values needed for authentication
pveum user token add terraform@pve terraform-automation --privsep 0
```

### Create ```terraform/terraform.tfvars``` file

Create the secrets file with values from the last command

```hcl
pm_api_url = "<your proxmox api url>"
pm_api_token_id = "<your proxmox user>"
pm_api_token_secret = "<proxmox user api token>"
```

### Terraform validate and apply

```bash
cd terraform
terraform init
terraform plan
terraform apply
```

## Packer Docs

Check Packer [documentation](./packer/README.md)

## Terraform Docs

Check Terraform [documentation](./terraform/README.md)

## References

- [Proxmox VE Documentation](https://pve.proxmox.com/pve-docs/)
- [Proxmox Cloud-Init Support](https://pve.proxmox.com/wiki/Cloud-Init_Support)
- [Proxmox Cloud-Init FAQ](https://pve.proxmox.com/wiki/Cloud-Init_FAQ)
