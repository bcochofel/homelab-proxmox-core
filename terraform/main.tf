# ----------------------------------------------------------------------------
# Caddy reverse-proxy VM on Proxmox.
# Packer template -> Terraform clones the VM + generates Ansible inventory.
# ----------------------------------------------------------------------------

# Look up the template's VMID by name so tfvars can reference it by name.
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

# DNS node (CoreDNS + Pihole, two Docker Compose services on one VM)
module "dns" {
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

# ----------------------------------------------------------------------------
# Generate Ansible inventory.
# Only hosts.ini is generated — group_vars/ stays hand-authored so Terraform
# never clobbers tuning.
# ----------------------------------------------------------------------------
resource "local_file" "ansible_inventory" {
  content = templatefile("${path.root}/templates/inventory.ini.tftpl", {
    caddy_name   = module.caddy.name
    caddy_ip     = module.caddy.ip
    dns_name     = module.dns.name
    dns_ip       = module.dns.ip
    ansible_user = var.ansible_user
  })
  filename = "${path.root}/../ansible/inventory/hosts.ini"
}
