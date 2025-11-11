# Ubuntu 24.04 Proxmox Packer Template

This repository defines a **production-ready, hardened Ubuntu 24.04 LTS base image** built with **Packer** for **Proxmox**.
It follows **immutable infrastructure principles**, integrates with **GitLab CI/CD**, and is designed for **repeatable, secure, and modular deployments**.

---

## 🧱 Overview

This template automates the provisioning of an Ubuntu 24.04 image with:

- **Cloud-init** and **Autoinstall** integration
- **Proxmox ISO builder** (`proxmox-iso`)
- **QEMU Guest Agent** preinstalled
- **Docker CE** (optional via variable)
- **Grafana Alloy** (replaces Grafana Agent) for host + Docker metrics and logs
- **Custom CA import support** (`custom-ca/`) for internal PKI
- **Strict security hardening** (root disabled, SSH hardened, IPv6 disabled)
- **Immutable cleanup & sealing** before converting to a template

---

## 📁 Repository Structure

```txt
.
├── ubuntu-24.04.pkr.hcl             # Main Packer template definition
├── variables.pkr.hcl                # Input variables (user-defined)
├── versions.pkr.hcl                 # Plugin versions and dependencies
├── locals.pkr.hcl                   # Local helper variables
├── http/
│   ├── user-data.yml.tpl            # Cloud-init Autoinstall configuration
│   └── meta-data.yml
├── alloy/                           # Modular Grafana Alloy configs
│   ├── base.yaml
│   ├── host-metrics.yaml
│   ├── host-logs.yaml
│   ├── docker-metrics.yaml
│   ├── docker-logs.yaml
│   └── prometheus-loki.yaml
├── custom-ca/                       # (Optional) Root CA certificates to import
│   ├── mycorp-root-ca.crt
│   └── team-intermediate.pem
└── scripts/
    ├── 00-configure-proxy.sh
    ├── 10-install-docker.sh
    ├── 15-install-custom-ca.sh
    ├── 20-install-alloy.sh
    ├── 80-disable-root-login.sh
    ├── 81-disable-ipv6.sh
    ├── 82-disable-cloudinit-updates.sh
    ├── 90-verify-system.sh
    └── 99-cleanup-seal.sh
```

---

## ⚙️ Configuration Variables

The variables are defined in `variables.pkr.hcl`. They can be overridden via:

- `packer build -var-file=variables.pkrvars.hcl`
- Environment variables (e.g., `PKR_VAR_proxmox_api_url`)

| Variable | Description | Default |
|-----------|-------------|----------|
| `proxmox_api_url` | Proxmox API endpoint | — |
| `proxmox_api_token_id` | Token ID for API authentication | — |
| `proxmox_api_token_secret` | Token secret | — |
| `proxmox_node` | Target Proxmox node name | `pve1` |
| `proxmox_storage_pool` | Storage pool for disks and ISOs | `local-lvm` |
| `proxmox_bridge` | Network bridge | `vmbr0` |
| `vm_name` | Name of resulting template | `ubuntu-24-04-template` |
| `vm_id` | Numeric VM ID | `9000` |
| `vm_cpu_cores` | CPU cores | `2` |
| `vm_cpu_sockets` | CPU sockets | `1` |
| `vm_cpu_type` | CPU type | `host` |
| `vm_memory` | Memory (MB) | `2048` |
| `disk_size` | Disk size (GB) | `20` |
| `vm_timezone` | System timezone | `UTC` |
| `vm_locale` | Default locale | `en_US.UTF-8` |
| `ssh_username` | Primary user | `ubuntu` |
| `ssh_public_key` | Public key for SSH login | — |
| `enable_proxy` | Whether to configure proxy | `false` |
| `install_docker` | Whether to install Docker | `true` |
| `install_alloy` | Whether to install Grafana Alloy | `true` |

---

## 🔐 Security Hardening

The image enforces the following security controls:

### SSH

- **Root login disabled** (`PermitRootLogin no`)
- **Password authentication disabled** (`PasswordAuthentication no`)
- **Key-only SSH** (via cloud-init authorized keys)
- Optional **console password login** for `ssh_username` (if autoinstall sets a password hash)
- SSH configuration hardened in `scripts/80-disable-root-login.sh`

### Users

- Root account locked (`passwd -l root`)
- Main user unlocked for console (optional)
- Sudo privileges configured via `/etc/sudoers.d/90-cloud-init-users`
- Duplicate sudoers entries automatically cleaned during sealing

### Network

- **IPv6 disabled** in sysctl and GRUB
- Optional HTTP/HTTPS proxy configuration
- `no_proxy` support for internal services

### Updates and cloud-init

- **Automatic package upgrades disabled** by `/etc/cloud/cloud.cfg.d/99-disable-updates.cfg`
- `apt-daily` and `apt-daily-upgrade` timers disabled
- Ensures clones never perform network upgrades on first boot

### Time sync

- `systemd-timesyncd` enabled and verified
- NTP synchronization validated before sealing

---

## 🧩 Grafana Alloy (Observability)

Grafana Alloy replaces the legacy Grafana Agent and provides unified telemetry collection.

### Modular configuration

All configuration fragments are located in `alloy/` and copied into `/etc/alloy/conf.d/`.

| File | Purpose |
|------|----------|
| `base.yaml` | Global settings (server, listen address) |
| `host-metrics.yaml` | Collect CPU, memory, disk, network metrics from the host |
| `host-logs.yaml` | Collect journald + `/var/log/*` logs |
| `docker-metrics.yaml` | Collect container metrics from Docker socket or cAdvisor |
| `docker-logs.yaml` | Collect container logs (journald or json-file) |
| `prometheus-loki.yaml` | Define Prometheus and Loki endpoints (empty by default) |

Example main config:

```yaml
configs:
  - /etc/alloy/conf.d/base.yaml
  - /etc/alloy/conf.d/host-metrics.yaml
  - /etc/alloy/conf.d/host-logs.yaml
  - /etc/alloy/conf.d/docker-metrics.yaml
  - /etc/alloy/conf.d/docker-logs.yaml
  - /etc/alloy/conf.d/prometheus-loki.yaml
```

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
packer validate ubuntu-24.04.pkr.hcl
packer build -var-file=variables.pkrvars.hcl ubuntu-24.04.pkr.hcl
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
- Graceful shutdown

---

## 🧪 Verification (scripts/90-verify-system.sh)

Before sealing, the system runs automated validation checks:

- **Systemd-timesyncd**: synchronized
- **QEMU Guest Agent**: running
- **Docker daemon**: active
- **Alloy service**: active
- **IPv6 disabled**
- **No zombie processes**
- **LVM + mount check** for `/opt` and root volumes

Build aborts if any of these checks fail.

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

## 🧾 Troubleshooting

| Symptom | Cause | Fix |
|----------|--------|----|
| Cloud-init upgrades packages on first boot | Missing or invalid `/etc/cloud/cloud.cfg.d/99-disable-updates.cfg` | Ensure script `82-disable-cloudinit-updates.sh` runs and file exists |
| Console login fails | Account locked (`!` prefix in `/etc/shadow`) | Unlock in `80-disable-root-login.sh` or autoinstall password |
| `checksum mismatch (file change by other user?) (500)` | Cloud-init seed modified post-install | Ensure only static `/etc/cloud/cloud.cfg.d` files are touched |
| Alloy not running | Wrong service name (`grafana-alloy` vs `alloy`) | Confirm correct unit name in systemd |
| Proxy not applied | Variables not exported globally | Verify `/etc/environment` and `/etc/apt/apt.conf.d/proxy.conf` |

---

## 📌 Notes

- Template is **immutable** and **secure by default**
- Console login only for emergency troubleshooting
- System updates must be handled via CI/CD or Ansible
- Grafana Alloy config is modular and extensible
- Cloud-init configuration prevents first-boot drift
- Use GitLab CI templates for **pre-commit**, **semantic-release**, and **packer build automation**

---

Maintainer: **DevOps Team <devops-team@example.com>**
