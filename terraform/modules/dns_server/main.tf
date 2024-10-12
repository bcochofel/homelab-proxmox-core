resource "random_pet" "dns" {
}

resource "proxmox_lxc" "dns" {
  target_node  = var.target_node
  hostname     = var.hostname != "" ? var.hostname : random_pet.dns.id
  ostemplate   = var.ostemplate
  password     = var.password
  unprivileged = var.unprivileged

  // CPU/Memory
  cores    = var.cores
  cpulimit = var.cpulimit
  memory   = var.memory
  swap     = var.swap

  // Terraform will crash without rootfs defined
  rootfs {
    storage = var.rootfs_storage
    size    = var.rootfs_size
  }

  network {
    name     = var.network_name
    bridge   = var.network_bridge
    ip       = var.network_ip_cidr
    gw       = var.network_gw
    firewall = var.network_fw
  }

  ssh_public_keys = var.ssh_public_keys

  onboot = var.onboot
  start  = var.start

  nameserver   = var.nameserver
  searchdomain = var.searchdomain

  tags = var.tags
}
