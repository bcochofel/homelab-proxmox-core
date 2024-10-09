# Packer Images for Ubuntu
[![pre-commit](https://img.shields.io/badge/pre--commit-enabled-brightgreen?logo=pre-commit&logoColor=white)](https://github.com/pre-commit/pre-commit)
[![GitHub license](https://img.shields.io/github/license/bcochofel/packer-proxmox-ubuntu.svg)](https://github.com/bcochofel/packer-proxmox-ubuntu/blob/master/LICENSE)
[![GitHub tag (latest by date)](https://img.shields.io/github/v/tag/bcochofel/packer-proxmox-ubuntu)](https://github.com/bcochofel/packer-proxmox-ubuntu/tags)
[![GitHub issues](https://img.shields.io/github/issues/bcochofel/packer-proxmox-ubuntu.svg)](https://github.com/bcochofel/packer-proxmox-ubuntu/issues/)
[![GitHub forks](https://img.shields.io/github/forks/bcochofel/packer-proxmox-ubuntu.svg?style=social&label=Fork&maxAge=2592000)](https://github.com/bcochofel/packer-proxmox-ubuntu/network/)
[![GitHub stars](https://img.shields.io/github/stars/bcochofel/packer-proxmox-ubuntu.svg?style=social&label=Star&maxAge=2592000)](https://github.com/bcochofel/packer-proxmox-ubuntu/stargazers/)

Build Ubuntu Images for Proxmox using Packer

## Proxmox Setup

Create Packer User/Group/<Pool> and set permissions

```bash
# create role and set privileges
pveum role add PackerProv -privs  "Pool.Audit Datastore.AllocateSpace Datastore.Allocate Datastore.Audit VM.Allocate VM.Audit VM.Backup VM.Clone VM.Config.CDROM VM.Config.CPU VM.Config.Cloudinit VM.Config.Disk VM.Config.HWType VM.Config.Memory VM.Config.Network VM.Config.Options VM.Console VM.Migrate VM.Monitor VM.PowerMgmt VM.Snapshot VM.Snapshot.Rollback SDN.Use"
# create user
pveum user add packer@pve --password Pack3rPr0v1s10n1ng
# set permissions
pveum aclmod / -user packer@pve -role PackerProv

# set permissions (only for the resource pool)
# create resource pool
#pveum pool add packer --comment "Hashicorp Packer Images"
#pveum aclmod /pool/packer -user packer@pve -role PackerProv
```

Create API Token

```bash
pveum user token add packer@pve packer-automation --privsep 0
```

**Note:** The above command will output the values you need to use in to authenticate

## Validate

You can validate the template using

```bash
packer validate ubuntu-server/
```

## Build

Create the ```ubuntu-server/secrets.auto.pkrvars.hcl``` file with values from previous steps

```hcl
pm_api_url = "<your proxmox api url>"
pm_api_token_id = "<your proxmox user>"
pm_api_token_secret = "<proxmox user api token>"
```

To build proxmox images for Ubuntu Server run (it will build all the sources defined in the folder)

```bash
packer build ubuntu-server/
```

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

- [Proxmox VE Documentation](https://pve.proxmox.com/pve-docs/)
- [Proxmox Cloud-Init Support](https://pve.proxmox.com/wiki/Cloud-Init_Support)
- [Proxmox Cloud-Init FAQ](https://pve.proxmox.com/wiki/Cloud-Init_FAQ)
- [Proxmox Packer Builder](https://developer.hashicorp.com/packer/integrations/hashicorp/proxmox)
- [Packer User/Group and Permissions](https://github.com/hashicorp/packer-plugin-proxmox/issues/184)
- [Cloud-Init Documentation](https://cloudinit.readthedocs.io/en/latest/reference/index.html)
- [Ubuntu Cloud Images](https://cloud-images.ubuntu.com/)
- [Ubuntu autoinstall](https://canonical-subiquity.readthedocs-hosted.com/en/latest/reference/autoinstall-reference.html)
- [Accessing Network Applications with WSL](https://learn.microsoft.com/en-us/windows/wsl/networking)
- [Configure Hyper-V firewall](https://learn.microsoft.com/en-us/windows/security/operating-system-security/network-security/windows-firewall/hyper-v-firewall)
- [Chrian Lempa boilerplates](https://github.com/ChristianLempa/boilerplates)
