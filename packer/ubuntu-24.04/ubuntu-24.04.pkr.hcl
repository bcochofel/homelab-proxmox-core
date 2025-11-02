# Source
source "proxmox-iso" "ubuntu-24-04" {
  # Proxmox connection
  proxmox_url              = var.proxmox_api_url
  username                 = var.proxmox_api_token_id
  token                    = var.proxmox_api_token_secret
  insecure_skip_tls_verify = true
  node                     = var.proxmox_node

  # VM Settings
  vm_id                = var.vm_id
  vm_name              = var.vm_name
  template_description = var.vm_description

  # ISO
  boot_iso {
    type     = "scsi"
    iso_file = "local:iso/ubuntu-24.04.1-live-server-amd64.iso"
    unmount  = true
  }

  # System
  qemu_agent      = true
  scsi_controller = "virtio-scsi-single"

  # Disks
  disks {
    disk_size    = var.disk_size
    storage_pool = var.proxmox_storage_pool
    type         = "scsi"
    format       = "raw"
    io_thread    = true
    ssd          = true
    discard      = true
  }

  # CPU
  cores    = var.vm_cpu_cores
  sockets  = var.vm_cpu_sockets
  cpu_type = var.vm_cpu_type

  # Memory
  memory = var.vm_memory

  # Network
  network_adapters {
    model    = "virtio"
    bridge   = var.network_bridge
    firewall = false
  }

  # Cloud-Init
  cloud_init              = true
  cloud_init_storage_pool = var.proxmox_storage_pool

  # Boot
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

  # HTTP content - serve from locals
  http_content = {
    "/user-data" = local.user_data
    "/meta-data" = local.meta_data
  }
  http_interface = "eth0"

  # SSH
  ssh_username         = var.ssh_username
  ssh_private_key_file = var.ssh_private_key_file
  # if ssh key has password use the agent
  #ssh_agent_auth = true
  ssh_timeout = var.ssh_timeout

  # Set tags
  tags = "${var.tags};noble"
}

# Build
build {
  sources = ["source.proxmox-iso.ubuntu-24-04"]

  # Wait for cloud-init to complete
  provisioner "shell" {
    inline = [
      "while [ ! -f /var/lib/cloud/instance/boot-finished ]; do echo 'Waiting for cloud-init...'; sleep 1; done",
      "sudo cloud-init status --wait"
    ]
  }

  # Conditional proxy setup
  provisioner "shell" {
    execute_command = "sudo bash '{{ .Path }}'"
    scripts = [
      "${path.root}/scripts/01_configure_proxy.sh",
    ]
    only = ["proxmox-iso.ubuntu"]
    environment_vars = [
      "USE_PROXY=${var.use_proxy}",
      "HTTP_PROXY=${var.http_proxy}",
      "HTTPS_PROXY=${var.https_proxy}",
      "NO_PROXY=${var.no_proxy}"
    ]
  }

  # Docker installation
  provisioner "shell" {
    execute_command = "sudo bash '{{ .Path }}'"
    scripts = [
      "${path.root}/scripts/02_install_docker.sh",
    ]
    only = ["proxmox-iso.ubuntu"]
    environment_vars = [
      "USE_PROXY=${var.use_proxy}",
      "HTTP_PROXY=${var.http_proxy}",
      "HTTPS_PROXY=${var.https_proxy}",
      "NO_PROXY=${var.no_proxy}"
    ]
  }

  # Grafana Alloy (conditional)
  provisioner "shell" {
    execute_command = "sudo bash '{{ .Path }}'"
    scripts = [
      "${path.root}/scripts/03_install_alloy.sh",
    ]
    environment_vars = [
      "USE_ALLOY=${var.use_alloy}",
      "PROM_ENDPOINTS=${join(",", var.prometheus_endpoints)}",
      "LOKI_ENDPOINTS=${join(",", var.loki_endpoints)}",
      "ALLOY_VERSION=${var.alloy_version}"
    ]
  }

  # Verify installations
  provisioner "shell" {
    inline = [
      "echo '=== System Info ==='",
      "cat /etc/os-release",
      "echo ''",
      "echo '=== Hostname ==='",
      "hostnamectl",
      "echo ''",
      "echo '=== Locale ==='",
      "localectl",
      "echo ''",
      "echo '=== Timezone ==='",
      "timedatectl",
      "echo ''",
      "echo '=== LVM Configuration ==='",
      "sudo vgdisplay",
      "sudo lvdisplay",
      "echo ''",
      "echo '=== Disk Usage ==='",
      "df -h",
      "echo ''",
      "echo '=== Docker Version ==='",
      "docker --version",
      "sudo systemctl status docker --no-pager",
      "echo ''",
      "echo '=== Docker Compose Version ==='",
      "docker compose version",
      "echo ''",
      "echo '=== Users ==='",
      "cat /etc/passwd | grep -E '(ubuntu|1000)'"
    ]
  }

  # Final cleanup
  provisioner "shell" {
    inline = [
      "sudo apt-get autoremove -y",
      "sudo apt-get clean",
      "sudo cloud-init clean",
      "sudo rm -f /etc/cloud/cloud.cfg.d/99-installer.cfg",
      "sudo rm -f /etc/cloud/cloud.cfg.d/subiquity-disable-cloudinit-networking.cfg",
      "sudo truncate -s 0 /etc/machine-id",
      "sudo rm -f /var/lib/dbus/machine-id",
      "sudo ln -s /etc/machine-id /var/lib/dbus/machine-id",
      "sudo rm -f /tmp/setup.sh",
      "sudo sync"
    ]
  }
}
