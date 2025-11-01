# Ubuntu 24.04 LTS Template with Packer + Proxmox

This setup builds a **Proxmox VM Template** for Ubuntu 24.04 using Packer and autoinstall + cloud-init.

## 🚀 Features

- Proxmox ISO build with `ubuntu-24.04-live-server-amd64.iso`
- Autoinstall and cloud-init support
- System-wide HTTP/HTTPS/NO_PROXY configuration (optional)
- Docker installed and configured
- Optional Grafana Alloy installation (Prometheus, Loki, journald, syslog, Docker logs)
- Secure SSH (no root login, key-based only)
- QEMU Guest Agent enabled

---

## ⚙️ Files Overview

| File | Description |
|------|--------------|
| `variables.pkr.hcl` | Define parameters like proxy, NTP, users, packages, Alloy config |
| `ubuntu2404.pkr.hcl` | Main Packer template (build logic + provisioners) |
| `http/user-data.tmpl` | Ubuntu autoinstall configuration |
| `http/meta-data` | Cloud-init metadata |
| `README.md` | This file |

---

## 🧩 Usage

### Edit variables

Edit `variables.pkr.hcl` to fit your environment:

```hcl
use_proxy  = true
http_proxy = "http://proxy.example.com:3128"
https_proxy = "http://proxy.example.com:3128"
no_proxy = "localhost,127.0.0.1,.example.com"

use_alloy = true
prometheus_endpoints = ["http://prometheus:9090/api/v1/write"]
loki_endpoints = ["http://loki:3100/loki/api/v1/push"]
```

### Run the build

```bash
packer init .
packer build -var-file=variables.pkr.hcl ubuntu2404.pkr.hcl
```

### Result

After completion, a VM template named `ubuntu-2404-template` will be available in Proxmox.

---

## 🧱 Notes

- To disable Alloy installation, set `use_alloy = false`
- To disable proxy configuration, set `use_proxy = false`
- You can expand `users` and `packages` in `variables.pkr.hcl`
