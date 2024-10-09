provider "proxmox" {
  # Configuration options
  pm_api_url          = var.pm_api_url
  pm_api_token_id     = var.pm_api_token_id
  pm_api_token_secret = var.pm_api_token_secret

  pm_tls_insecure = true
}

provider "random" {
  # Configuration options
}

resource "random_pet" "bind9" {
}

resource "proxmox_lxc" "basic" {
  target_node  = "pve"
  hostname     = random_pet.bind9.id
  ostemplate   = "local:vztmpl/ubuntu-24.04-standard_24.04-2_amd64.tar.zst"
  password     = var.lxc_password
  unprivileged = true

  // CPU/Memory
  cores    = 2
  cpulimit = 2
  memory   = 512
  swap     = 512

  // Terraform will crash without rootfs defined
  rootfs {
    storage = "local-lvm"
    size    = "8G"
  }

  network {
    name     = "eth0"
    bridge   = "vmbr0"
    ip       = "${var.lxc_ip}/22"
    gw       = "192.168.68.1"
    firewall = false
  }

  ssh_public_keys = <<-EOT
    ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIEZGQwHOs8V9ndmLn3NuQXxuD0Ht4zaz+c6/WaEMAA6S bcochofel@NUC12WSHi7
  EOT

  onboot = true
  start  = true

  tags = "terraform;bind9"

  connection {
    type     = "ssh"
    host     = var.lxc_ip
    user     = "root"
    password = var.lxc_password
  }

  provisioner "remote-exec" {
    inline = [
      "sudo apt update",
      "sudo apt install -y bind9 bind9utils bind9-doc dnsutils"
    ]
  }
}

resource "terraform_data" "named_conf_options" {
  input = filemd5("${path.root}/files/named.conf.options")
}

resource "terraform_data" "named_conf_local" {
  input = filemd5("${path.root}/files/named.conf.local")
}

resource "terraform_data" "bind9" {
  lifecycle {
    replace_triggered_by = [
      terraform_data.named_conf_options,
      terraform_data.named_conf_local
    ]
  }

  connection {
    type     = "ssh"
    host     = var.lxc_ip
    user     = "root"
    password = var.lxc_password
  }

  provisioner "file" {
    source      = "${path.root}/files/"
    destination = "/etc/bind"
  }

  provisioner "remote-exec" {
    inline = [
      "sudo systemctl start named",
      "sudo systemctl enable named"
    ]
  }
}
