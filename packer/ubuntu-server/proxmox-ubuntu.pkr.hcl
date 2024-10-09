# Ubuntu Jammy template
source "proxmox-iso" "jammy" {

  # Proxmox Connection Settings
  proxmox_url = "${var.pm_api_url}"
  username    = "${var.pm_api_token_id}"
  token       = "${var.pm_api_token_secret}"

  insecure_skip_tls_verify = true

  # VM ID/name
  vm_id                = 5000
  vm_name              = "ubuntu-jammy-tmpl"
  template_description = "Ubuntu Jammy Server Image"

  # VM General Settings
  node = local.node

  # VM OS Settings
  boot_iso {
    type     = "scsi"
    iso_file = "local:iso/ubuntu-22.04.5-live-server-amd64.iso"
    unmount  = true
  }

  # VM System Settings
  qemu_agent = local.qemu_agent

  # VM CPU/Memory Settings
  cpu_type = local.cpu_type
  memory   = local.memory
  sockets  = local.sockets
  cores    = local.cores

  # VM Hard Disk Settings
  scsi_controller = local.scsi_controller

  disks {
    type         = local.type
    disk_size    = local.disk_size
    format       = local.format
    storage_pool = local.storage_pool
  }

  # VM Network Settings
  network_adapters {
    bridge   = local.bridge
    firewall = local.firewall
  }

  # VM cloud-init Settings
  cloud_init              = local.ci
  cloud_init_storage_pool = local.ci_storage_pool

  # Packer Boot Commands
  boot_command = [
    "<esc><wait>",
    "e<wait>",
    "<down><down><down><end>",
    "<bs><bs><bs><bs><wait>",
    "autoinstall ds=nocloud-net\\;s=http://{{ .HTTPIP }}:{{ .HTTPPort }}/ ---<wait>",
    "<f10><wait>"
  ]
  boot      = "c"
  boot_wait = "5s"

  # Packer Autoinstall Settings
  http_directory = "${path.root}/http"
  http_interface = "eth0"

  # Packer SSH Settings
  ssh_username         = "${var.ssh_username}"
  ssh_private_key_file = "${var.ssh_private_key_file}"
  # if ssh key has password use the agent
  #ssh_agent_auth = true

  # Raise the timeout, when installation takes longer
  ssh_timeout = "20m"

  # Set tags
  tags = "ubuntu;ubuntu-jammy;template"
}

# Ubuntu Noble template
source "proxmox-iso" "noble" {

  # Proxmox Connection Settings
  proxmox_url = "${var.pm_api_url}"
  username    = "${var.pm_api_token_id}"
  token       = "${var.pm_api_token_secret}"

  insecure_skip_tls_verify = true

  # VM ID/name
  vm_id                = 5001
  vm_name              = "ubuntu-noble-tmpl"
  template_description = "Ubuntu Noble Server Image"

  # VM General Settings
  node = local.node

  # VM OS Settings
  boot_iso {
    type     = "scsi"
    iso_file = "local:iso/ubuntu-24.04.1-live-server-amd64.iso"
    unmount  = true
  }

  # VM System Settings
  qemu_agent = local.qemu_agent

  # VM CPU/Memory Settings
  cpu_type = local.cpu_type
  memory   = local.memory
  sockets  = local.sockets
  cores    = local.cores

  # VM Hard Disk Settings
  scsi_controller = local.scsi_controller

  disks {
    type         = local.type
    disk_size    = local.disk_size
    format       = local.format
    storage_pool = local.storage_pool
  }

  # VM Network Settings
  network_adapters {
    bridge   = local.bridge
    firewall = local.firewall
  }

  # VM cloud-init Settings
  cloud_init              = local.ci
  cloud_init_storage_pool = local.ci_storage_pool

  # Packer Boot Commands
  boot_command = [
    "<esc><wait>",
    "e<wait>",
    "<down><down><down><end>",
    "<bs><bs><bs><bs><wait>",
    "autoinstall ds=nocloud-net\\;s=http://{{ .HTTPIP }}:{{ .HTTPPort }}/ ---<wait>",
    "<f10><wait>"
  ]
  boot      = "c"
  boot_wait = "5s"

  # Packer Autoinstall Settings
  http_directory = "${path.root}/http"
  http_interface = "eth0"

  # Packer SSH Settings
  ssh_username         = "${var.ssh_username}"
  ssh_private_key_file = "${var.ssh_private_key_file}"
  # if ssh key has password use the agent
  #ssh_agent_auth = true

  # Raise the timeout, when installation takes longer
  ssh_timeout = "20m"

  # Set tags
  tags = "ubuntu;ubuntu-noble;template"
}

# Build Definition to create the VM Template
build {
  sources = [
    "source.proxmox-iso.jammy",
    "source.proxmox-iso.noble"
  ]

  # sealing virtual machine
  provisioner "shell" {
    inline = [
      "while [ ! -f /var/lib/cloud/instance/boot-finished ]; do echo 'Waiting for cloud-init...'; sleep 1; done",
      "sudo rm /etc/ssh/ssh_host_*",
      "sudo apt -y autoremove --purge",
      "sudo apt -y clean",
      "sudo apt -y autoclean",
      "sudo cloud-init clean --logs --machine-id",
      "sudo sync"
    ]
  }

  # disable IPv6
  provisioner "shell" {
    script = "${path.root}/scripts/disable_ipv6.sh"
  }

  # docker installation
  provisioner "shell" {
    script = "${path.root}/scripts/install_docker.sh"
  }
}
