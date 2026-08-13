# Copy to terraform.tfvars (gitignored) or set as HCP workspace variables.

proxmox_endpoint = "https://192.168.68.20:8006/"
# Set TF_VAR_proxmox_api_token in env / HCP (sensitive):
#   terraform@pve!tf=xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
proxmox_insecure = true
target_node      = "pve1"

vm_template = "ubuntu-26.04-core"

gateway        = "192.168.68.1"
network_bridge = "vmbr0"
# CoreDNS (ns1) then Pihole (ns2) — used by every VM except dns itself.
# dns_node_nameserver (default 1.1.1.1/8.8.8.8) covers the dns VM, since it
# can't use its own not-yet-running macvlan IPs as its OS resolver.
nameserver   = ["192.168.68.42", "192.168.68.43"]
searchdomain = "homelab.bcochofel.com"

ciuser = "ubuntu"
# Set TF_VAR_cipassword in env / HCP (sensitive)
sshkeys = "ssh-ed25519 AAAA... bcochofel@host"

# Defaults already size the Caddy VM (1 vCPU / 1 GB / 20 GB, 192.168.68.40)
# and the DNS VM (2 vCPU / 2 GB / 20 GB, 192.168.68.41 — CoreDNS/Pihole get
# their own Docker macvlan IPs, .42/.43, configured by Ansible, not here).
# Override caddy_node/dns_node here only if you want a different VMID, IP,
# or sizing.
