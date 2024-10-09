provider "proxmox" {
  # Configuration options
  pm_api_url          = var.pm_api_url
  pm_api_token_id     = var.pm_api_token_id
  pm_api_token_secret = var.pm_api_token_secret

  pm_tls_insecure = true
}

module "dev_workstation" {
  source = "./modules/dev_workstation"

  vm_template = "ubuntu-noble-tmpl"

  memory = 2048
  cores  = 2

  gateway = "192.168.68.1"
  ip_cidr = "192.168.68.73/22"
}
