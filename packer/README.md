# Packer Images for Ubuntu

Build Ubuntu Images for Proxmox using Packer

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
- [Ubuntu Cloud Images](https://cloud-images.ubuntu.com/)
- [Ubuntu autoinstall](https://canonical-subiquity.readthedocs-hosted.com/en/latest/reference/autoinstall-reference.html)
- [Accessing Network Applications with WSL](https://learn.microsoft.com/en-us/windows/wsl/networking)
- [Configure Hyper-V firewall](https://learn.microsoft.com/en-us/windows/security/operating-system-security/network-security/windows-firewall/hyper-v-firewall)
- [Chrian Lempa boilerplates](https://github.com/ChristianLempa/boilerplates)
