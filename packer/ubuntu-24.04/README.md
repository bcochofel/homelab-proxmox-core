# Ubuntu 24.04 Proxmox Packer Template

This repository defines a **production-ready, hardened Ubuntu 24.04 LTS base image** built with **Packer**.
It follows **immutable infrastructure principles**, integrates with **GitLab CI/CD**, and is designed for **repeatable, secure, and modular deployments**.

---

## 🧱 Overview

This template automates the provisioning of an Ubuntu 24.04 image with:

- **Cloud-init** and **Autoinstall** integration
- **Docker CE** (optional via variable)
- **Grafana Alloy** (replaces Grafana Agent) for host + Docker metrics and logs
- **Custom CA import support** (`custom-ca/`) for internal PKI
- **Strict security hardening** (root disabled, SSH hardened, IPv6 disabled)
- **Immutable cleanup & sealing** before converting to a template

---

## ⚙️ Configuration Variables

The variables are defined in `variables.pkr.hcl`. They can be overridden via:

- `packer build -var-file=variables.pkrvars.hcl`
- Environment variables (e.g., `PKR_VAR_proxmox_api_url`)

<!-- VARIABLES_TABLE_START -->
| Variable | Description | Type | Default | Required |
|----------|-------------|------|---------|----------|
| `additional_users` | Additional users to create | `${list(object({"name": "string", "groups": "${list(string)}", "sudo": "string", "shell": "string", "ssh_authorized_keys": "${list(string)}", "lock_passwd": "bool"}))}` | `[]` | No |
| `boot_iso_file` | Ubuntu ISO local file | `string` | `"local:iso/ubuntu-24.04.3-li..."` | No |
| `boot_iso_type` | Boot ISO type | `string` | `"scsi"` | No |
| `boot_iso_unmount` | Unmount ISO after installation? | `bool` | `true` | No |
| `disk_size` | Disk size | `string` | `"60G"` | No |
| `disk_type` | Disk Type | `string` | `"scsi"` | No |
| `enable_proxy` | Whether to configure system-wide proxy settings | `bool` | `false` | No |
| `grafana_alloy_version` | Grafana Alloy version to install | `string` | `"1.11.3"` | No |
| `hostname` | System hostname | `string` | `"ubuntu-template"` | No |
| `http_proxy` | HTTP proxy address (e.g. <http://proxy.example.com:8080>) | `string` | `""` | No |
| `https_proxy` | HTTPS proxy address | `string` | `""` | No |
| `install_docker` | Wheter to install Docker | `bool` | `true` | No |
| `keyboard_layout` | Keyboard layout | `string` | `"us"` | No |
| `keyboard_variant` | Keyboard variant | `string` | `"intl"` | No |
| `locale` | System locale | `string` | `"en_US.UTF-8"` | No |
| `network_bridge` | Network bridge | `string` | `"vmbr0"` | No |
| `network_model` | Network Model | `string` | `"virtio"` | No |
| `no_proxy` | Comma-separated list of domains or IPs to exclude from proxy | `string` | `"localhost,127.0.0.1"` | No |
| `ntp_servers` | List of NTP servers | `${list(string)}` | `[...4 items]` | No |
| `packages` | List of packages to install | `${list(string)}` | `[...35 items]` | No |
| `password` | Default user password | `string` | - | Yes |
| `password_hash` | Default user password hashed. Use $ mkpasswd -m sha-512 '<yourpassword>' | `string` | - | Yes |
| `proxmox_api_token_id` | Proxmox API Token ID | `string` | - | Yes |
| `proxmox_api_token_secret` | Proxmox API Token Secret | `string` | - | Yes |
| `proxmox_api_url` | Proxmox API URL | `string` | - | Yes |
| `proxmox_node` | Proxmox node name | `string` | - | Yes |
| `proxmox_skip_tls_verify` | Skip TLS verification | `bool` | - | Yes |
| `qemu_agent` | - | `bool` | `true` | No |
| `scsi_controller` | - | `string` | `"virtio-scsi-single"` | No |
| `ssh_authorized_keys` | SSH authorized keys for default user | `${list(string)}` | `[]` | No |
| `ssh_private_key_file` | Private key file to use for SSH. | `string` | - | Yes |
| `ssh_timeout` | SSH timeout | `string` | `"20m"` | No |
| `storage_pool` | Storage pool for VM disk | `string` | `"local-lvm"` | No |
| `tags` | The tags to set. This is a semicolon separated list. For example, debian-12;t... | `string` | `"packer;ubuntu"` | No |
| `timezone` | System timezone | `string` | `"Europe/Lisbon"` | No |
| `username` | Default user | `string` | `"ubuntu"` | No |
| `vm_cpu_cores` | Number of CPU cores | `number` | `2` | No |
| `vm_cpu_sockets` | Number of CPU sockets | `number` | `1` | No |
| `vm_cpu_type` | CPU type | `string` | `"host"` | No |
| `vm_description` | VM template description | `string` | `"Ubuntu 24.04 LTS template"` | No |
| `vm_id` | VM template ID | `number` | `9000` | No |
| `vm_memory` | Memory in MB | `number` | `2048` | No |
| `vm_name` | VM template name | `string` | `"ubuntu-24.04-template"` | No |
<!-- VARIABLES_TABLE_END -->

---

## 🔐 Security Hardening

The image enforces the following security controls:

### SSH

- **Root login disabled** (`PermitRootLogin no`)
- **Password authentication disabled** (`PasswordAuthentication no`)
- **Key-only SSH** (via cloud-init authorized keys)
- Optional **console password login** for `ssh_username` (if autoinstall sets a password hash)

### Users

- Root account locked (`passwd -l root`)
- Main user unlocked for console (optional)
- Sudo privileges configured via `/etc/sudoers.d/90-cloud-init-users`
- Duplicate sudoers entries automatically cleaned during sealing

### Network

- **IPv6 disabled** in sysctl and GRUB
- Optional HTTP/HTTPS proxy configuration
- `no_proxy` support for internal services

### Time sync

- `systemd-timesyncd` enabled and verified
- NTP synchronization validated before sealing

---

## 🧩 Grafana Alloy (Observability)

Grafana Alloy replaces the legacy Grafana Agent and provides unified telemetry collection.

Alloy is configured to scrape metrics/logs from:

- host
- docker

After the VM is deployed, additional Alloy config fragments can be added under `/etc/alloy/conf.d/` to extend telemetry.

---

## 🧩 Custom CA Import

The build process checks for the folder `custom-ca/`.
All `.crt` or `.pem` files found there are copied to `/usr/local/share/ca-certificates/custom/` and trusted by running `update-ca-certificates`.

This allows:

- Internal PKI and HTTPS proxies
- Secure access to internal package registries, Docker registries, and GitLab runners

**Security rule:** never include private keys in `custom-ca/`.
Only public CA certificates are imported.

---

## 🧩 Proxy Configuration

Proxy configuration is modular and optional.
If `enable_proxy` is `true`, the following variables are used:

| Variable | Purpose |
|-----------|----------|
| `http_proxy` | HTTP proxy URL |
| `https_proxy` | HTTPS proxy URL |
| `no_proxy` | Comma-separated list of exceptions |

These are configured for:

- System environment (`/etc/environment`)
- APT configuration (`/etc/apt/apt.conf.d/`)
- Docker daemon (`/etc/systemd/system/docker.service.d/proxy.conf`)

---

## 🧩 Build Process

### Requirements

- Packer ≥ 1.10.x
- Proxmox 7.4+ or 8.x
- Ubuntu 24.04 ISO available in storage
- API token with VM template management privileges

### Steps

```bash
packer init .
packer validate .
packer build -var-file=variables.pkrvars.hcl .
```

**Outputs:**

- A sealed, hardened Proxmox VM template
- Manifest file for version tracking

---

## 🧹 Cleanup & Sealing

The final cleanup (`scripts/99-cleanup-seal.sh`) performs:

- Apt cache and log cleanup
- Cloud-init cleanup (`cloud-init clean --logs --machine-id`)
- Removal of `/var/lib/cloud/instances` and temporary data
- SSH host key regeneration on clone
- Disk zero-fill to optimize template compression

---

## 🧠 Design Decisions

| Decision | Reason |
|-----------|--------|
| **Cloud-init Autoinstall** | Reliable, unattended OS provisioning |
| **Immutable cleanup** | Prevent configuration drift across clones |
| **Root disabled by default** | Principle of least privilege |
| **User-unlock + console login** | Enable safe troubleshooting access |
| **No first-boot updates** | Faster and predictable provisioning |
| **Grafana Alloy modular config** | Extend telemetry easily post-deployment |
| **Proxy + CA injection** | Adapt to corporate environments securely |
| **IPv6 disabled** | Avoid unwanted dual-stack complexity |
| **Two-phase validation** | Catch errors before sealing |

---

## 📌 Notes

- Template is **immutable** and **secure by default**
- Console login only for emergency troubleshooting
- System updates must be handled via CI/CD or Ansible
- Grafana Alloy config is modular and extensible
- Cloud-init configuration prevents first-boot drift

---
