# Copy to terraform.tfvars (gitignored) or set as HCP workspace variables.

proxmox_endpoint = "https://192.168.68.20:8006/"
# proxmox_api_token and cipassword are never set here — they arrive as
# TF_VAR_* via hl_ro / tofu_rw (docs/CREDENTIALS.md).
proxmox_insecure = true
target_node      = "pve1"

vm_template = "ubuntu-26.04-core"

gateway        = "192.168.68.1"
network_bridge = "vmbr0"
# CoreDNS then Pihole (macvlan IPs on server01) — used by every VM except
# server01 itself.
# dns_node_nameserver (default 1.1.1.1/8.8.8.8) covers the dns VM, since it
# can't use its own not-yet-running macvlan IPs as its OS resolver.
nameserver   = ["192.168.68.2", "192.168.68.5"]
searchdomain = "homelab.bcochofel.com"

ciuser  = "ubuntu"
sshkeys = "ssh-ed25519 AAAA... bcochofel@host"

# Defaults already size the Caddy VM (proxy: 1 vCPU / 1 GB / 50 GB,
# 192.168.68.16) and the DNS VM (server01: 2 vCPU / 2 GB / 50 GB,
# 192.168.68.15 — CoreDNS/Pihole get their own Docker macvlan IPs, .2/.5,
# configured by Ansible, not here).
# Override caddy_node/dns_node here only if you want a different VMID, IP,
# or sizing.
