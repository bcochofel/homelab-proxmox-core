provider "proxmox" {
  # Configuration options
  pm_api_url          = var.pm_api_url
  pm_api_token_id     = var.pm_api_token_id
  pm_api_token_secret = var.pm_api_token_secret

  pm_tls_insecure = true
}

# create bind LXC
module "dns_server" {
  source = "./modules/dns_server"

  hostname = var.dns_hostname

  password = var.dns_root_password

  ssh_public_keys = var.ssh_pubkeys

  network_gw      = var.gateway
  network_ip_cidr = "${var.dns_ip}/22"

  nameserver   = var.nameserver
  searchdomain = var.searchdomain
}

# generate ansible inventory file
resource "local_file" "ansible_inventory" {
  content = templatefile("${path.root}/templates/inventory.tftpl", {
    "dns_ip" : var.dns_ip,
    "domain" : var.searchdomain,
    "network" : var.network,
    "dns_hostname" : var.dns_hostname }
  )
  filename = "${path.root}/../ansible/inventory"
}

# create developer workstation
module "dev_workstation" {
  source = "./modules/dev_workstation"

  vm_template = "ubuntu-noble-tmpl"

  memory = 2048
  cores  = 2

  gateway = var.gateway
  ip_cidr = "192.168.68.173/22"
}
