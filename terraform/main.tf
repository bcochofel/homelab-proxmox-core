# ----------------------------------------------------------------------------
# Caddy reverse-proxy VM on Proxmox.
# Packer template -> Terraform clones the VM + generates Ansible inventory.
# ----------------------------------------------------------------------------

# Look up the template's VMID by name (var.vm_template).
data "proxmox_virtual_environment_vms" "template" {
  node_name = var.target_node

  filter {
    name   = "name"
    values = [var.vm_template]
  }
}

locals {
  template_vmid = one(data.proxmox_virtual_environment_vms.template.vms).vm_id
}

# Caddy node
module "caddy" {
  source = "./modules/vm"

  name          = var.caddy_node.name
  vmid          = var.caddy_node.vmid
  target_node   = var.target_node
  template_vmid = local.template_vmid

  cores  = var.caddy_node.cores
  memory = var.caddy_node.memory
  disk   = var.caddy_node.disk

  ip_cidr        = var.caddy_node.ip_cidr
  gateway        = var.gateway
  network_bridge = var.network_bridge
  nameserver     = var.nameserver
  searchdomain   = var.searchdomain

  ciuser     = var.ciuser
  cipassword = var.cipassword
  sshkeys    = var.sshkeys

  tags = ["terraform", "caddy"]
}

# DNS node (CoreDNS + Pihole, two Docker Compose services on one VM).
# Module name matches the VM's Proxmox name/hostname ("server01"); the
# Ansible inventory group stays "dns" regardless (hardcoded in
# templates/inventory.ini.tftpl) — see CLAUDE.md.
module "server01" {
  source = "./modules/vm"

  name          = var.dns_node.name
  vmid          = var.dns_node.vmid
  target_node   = var.target_node
  template_vmid = local.template_vmid

  cores  = var.dns_node.cores
  memory = var.dns_node.memory
  disk   = var.dns_node.disk

  ip_cidr        = var.dns_node.ip_cidr
  gateway        = var.gateway
  network_bridge = var.network_bridge
  nameserver     = var.dns_node_nameserver
  searchdomain   = var.searchdomain

  ciuser     = var.ciuser
  cipassword = var.cipassword
  sshkeys    = var.sshkeys

  tags = ["terraform", "dns"]
}

# Self-hosted GitHub Actions runner for CI dry-runs (docs/RUNNER.md): only
# outbound connections, no Caddy site. Ansible inventory group
# "github_runner" (templates/inventory.ini.tftpl).
module "runner01" {
  source = "./modules/vm"

  name          = var.runner_node.name
  vmid          = var.runner_node.vmid
  target_node   = var.target_node
  template_vmid = local.template_vmid

  cores  = var.runner_node.cores
  memory = var.runner_node.memory
  disk   = var.runner_node.disk

  ip_cidr        = var.runner_node.ip_cidr
  gateway        = var.gateway
  network_bridge = var.network_bridge
  nameserver     = var.nameserver
  searchdomain   = var.searchdomain

  ciuser     = var.ciuser
  cipassword = var.cipassword
  sshkeys    = var.sshkeys

  tags = ["terraform", "github-runner"]
}

# ----------------------------------------------------------------------------
# Generate Ansible inventory.
# Only hosts.ini is generated — group_vars/ stays hand-authored so Terraform
# never clobbers tuning.
# ----------------------------------------------------------------------------
locals {
  ansible_inventory = templatefile("${path.root}/templates/inventory.ini.tftpl", {
    caddy_name   = module.caddy.name
    caddy_ip     = module.caddy.ip
    dns_name     = module.server01.name
    dns_ip       = module.server01.ip
    runner_name  = module.runner01.name
    runner_ip    = module.runner01.ip
    ansible_user = var.ansible_user
  })
}

resource "local_file" "ansible_inventory" {
  content  = local.ansible_inventory
  filename = "${path.root}/../ansible/inventory/hosts.ini"
}
