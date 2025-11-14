# Packer Images for Ubuntu

Build Ubuntu Images for Proxmox using Packer

## Prerequisites

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

### Build `packer/ubuntu-server`

Create the secrets file with values from the last command

```hcl
pm_api_url = "<your proxmox api url>"
pm_api_token_id = "<your proxmox user>"
pm_api_token_secret = "<proxmox user api token>"
```

Change the values of the variables ```ssh_username``` and ```ssh_private_key_file``` in the ```packer/ubuntu-server/variables.pkr.hcl``` file.

Be sure to upload the Ubuntu Server images needed for create the templates, check [this](packer/ubuntu-server/proxmox-ubuntu.pkr.hcl) file and search for ```iso_file``` entries.

```bash
packer init packer/ubuntu-server
packer validate packer/ubuntu-server
packer build packer/ubuntu-server
```

### Build `packer/ubuntu-24.04`

Create the variables file

```bash
cp variables.pkrvars.hcl.example variables.pkrvars.hcl
# edit variables file
vim variables.pkrvars.hcl
# Update proxmox_api_token_secret, passwords, and other settings
```

To build the `packer/ubuntu-24.04` template

```bash
cd packer/ubuntu-24.04
packer init .
packer validate -var-file="variables.pkrvars.hcl" .
packer build -var-file="variables.pkrvars.hcl" .
```

Testing

```bash
packer console -var-file="variables.pkrvars.hcl" .

> local.user_data
> local.fqdn
> var.packages
```

Features

- ✅ Ubuntu 24.04 LTS
- ✅ LVM storage layout (easy to extend)
- ✅ Docker and Docker Compose pre-installed
- ✅ Cloud-init ready
- ✅ QEMU Guest Agent
- ✅ Fully customizable via variables

## Running Packer from WSL2

To be able to run packer from WSL2 you need to change the network mode by creating a ```.wslconfig``` file

```init
# Settings apply across all Linux distros running on WSL 2
[wsl2]

# If the value is mirrored then this turns on mirrored networking mode. Default or unrecognized strings result in NAT networking.
networkingMode=mirrored

# Changes how DNS requests are proxied from WSL to Windows
dnsTunneling=true

# Enforces WSL to use Windows’ HTTP proxy information
autoProxy=true
```

To confirm if the mode is mirrored you can run the following command from WSL

```bash
wslinfo --networking-mode
```

and them create Firewall rules from a powershell terminal (admin)

The following sequence creates a Firewall Rule to allow TCP Inbound traffic through ports 8000-9000 (the default ports packer uses for the webserver)

```shell
wsl --version
Get-NetFirewallHyperVVMCreator
Get-NetFirewallHyperVVMSetting -PolicyStore ActiveStore -Name '{40E0AC32-46A5-438A-A0B2-2B479E8F2E90}'
New-NetFirewallHyperVRule -Name Packer-Inbound -DisplayName "Packer Inbound range" -Direction Inbound -VMCreatorId '{40E0AC32-46A5-438A-A0B2-2B479E8F2E90}' -Protocol TCP -LocalPorts 8000-9000
Get-NetFirewallHyperVRule -VMCreatorId '{40E0AC32-46A5-438A-A0B2-2B479E8F2E90}'
```

Check references for more information

## References

- [Proxmox Packer Builder](https://developer.hashicorp.com/packer/integrations/hashicorp/proxmox)
- [Packer User/Group and Permissions](https://github.com/hashicorp/packer-plugin-proxmox/issues/184)
- [Cloud-Init Documentation](https://cloudinit.readthedocs.io/en/latest/reference/index.html)
- [Cloud-init Module Reference](https://docs.cloud-init.io/en/latest/reference/modules.html)
- [Ubuntu autoinstall](https://canonical-subiquity.readthedocs-hosted.com/en/latest/reference/autoinstall-reference.html)
- [Ubuntu Cloud Images](https://cloud-images.ubuntu.com/)
- [Accessing Network Applications with WSL](https://learn.microsoft.com/en-us/windows/wsl/networking)
- [Configure Hyper-V firewall](https://learn.microsoft.com/en-us/windows/security/operating-system-security/network-security/windows-firewall/hyper-v-firewall)
- [Chrian Lempa boilerplates](https://github.com/ChristianLempa/boilerplates)
