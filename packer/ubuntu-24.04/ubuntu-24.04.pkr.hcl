# ==========================================================
# Packer Template: Ubuntu 24.04 LTS (Proxmox ISO)
# Modular layout — variables and versions are in separate files.
# ==========================================================

source "proxmox-iso" "ubuntu-24-04" {
  # --------------------------------------------------------
  # Proxmox connection
  # --------------------------------------------------------
  proxmox_url              = var.proxmox_api_url
  username                 = var.proxmox_api_token_id
  token                    = var.proxmox_api_token_secret
  node                     = var.proxmox_node
  insecure_skip_tls_verify = true

  # --------------------------------------------------------
  # VM Settings
  # --------------------------------------------------------
  vm_id                = var.vm_id
  vm_name              = var.vm_name
  template_description = var.vm_description

  # --------------------------------------------------------
  # ISO Boot configuration
  # --------------------------------------------------------
  boot_iso {
    type     = "scsi"
    iso_file = "local:iso/ubuntu-24.04.1-live-server-amd64.iso"
    unmount  = true
  }

  # --------------------------------------------------------
  # System configuration
  # --------------------------------------------------------
  qemu_agent      = true
  scsi_controller = "virtio-scsi-single"

  # --------------------------------------------------------
  # Disk and storage
  # --------------------------------------------------------
  disks {
    disk_size    = var.disk_size
    storage_pool = var.proxmox_storage_pool
    type         = "scsi"
    format       = "raw"
    io_thread    = true
    ssd          = true
    discard      = true
  }

  # --------------------------------------------------------
  # CPU and memory
  # --------------------------------------------------------
  cores    = var.vm_cpu_cores
  sockets  = var.vm_cpu_sockets
  cpu_type = var.vm_cpu_type
  memory   = var.vm_memory

  # --------------------------------------------------------
  # Network configuration
  # --------------------------------------------------------
  network_adapters {
    model    = "virtio"
    bridge   = var.network_bridge
    firewall = false
  }

  # --------------------------------------------------------
  # Cloud-init and autoinstall
  # --------------------------------------------------------
  cloud_init              = true
  cloud_init_storage_pool = var.proxmox_storage_pool

  http_content = {
    "/user-data" = local.user_data
    "/meta-data" = local.meta_data
  }
  http_interface = "eth0"

  # --------------------------------------------------------
  # Boot commands for autoinstall
  # --------------------------------------------------------
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

  # --------------------------------------------------------
  # SSH setup
  # --------------------------------------------------------
  ssh_username         = var.ssh_username
  ssh_private_key_file = var.ssh_private_key_file
  # if ssh key has password use the agent
  #ssh_agent_auth = true
  ssh_timeout = var.ssh_timeout

  # --------------------------------------------------------
  # Define Tags
  # --------------------------------------------------------
  tags = "${var.tags};noble"
}

# ==========================================================
# Build configuration
# ==========================================================
build {
  name    = "ubuntu-24-04-template"
  sources = ["source.proxmox-iso.ubuntu-24-04"]

  # --------------------------------------------------------
  # Wait for cloud-init to complete (non-root safe)
  # --------------------------------------------------------
  provisioner "shell" {
    inline = [
      "echo 'Waiting for cloud-init to finish...'",
      "while [ ! -f /var/lib/cloud/instance/boot-finished ]; do echo 'Waiting for cloud-init...'; sleep 1; done",
      "sudo cloud-init status --wait",
      "echo 'cloud-init finished.'"
    ]
    environment_vars = ["DEBIAN_FRONTEND=noninteractive"]
  }

  # -----------------------
  # Ensure alloy configs are available inside the guest
  # Use file provisioners to copy directories to the instance.
  # -----------------------
  provisioner "file" {
    source      = "${path.root}/alloy/"
    destination = "/tmp/alloy"
  }

  # -----------------------
  # Upload custom ROOT CA certificates
  # -----------------------
  provisioner "file" {
    source      = "${path.root}/custom-ca"
    destination = "/tmp/custom-ca"
  }

  # -----------------------
  # Run provisioning scripts (as root) — environment variables exported here
  # Keep execution order deterministic: proxy -> docker -> alloy
  # -----------------------
  provisioner "shell" {
    environment_vars = [
      "INSTALL_DOCKER=${var.install_docker}",
      "ENABLE_PROXY=${var.enable_proxy}",
      "HTTP_PROXY=${var.http_proxy}",
      "HTTPS_PROXY=${var.https_proxy}",
      "NO_PROXY=${var.no_proxy}",
      "GRAFANA_ALLOY_VERSION=${var.grafana_alloy_version}",
      "GRAFANA_ALLOY_URL=${var.grafana_alloy_url}"
    ]
    execute_command = "sudo -E bash '{{ .Path }}'"
    # Use absolute paths under /tmp/scripts so it's clear where they run from
    scripts = [
      "${path.root}/scripts/00-configure-proxy.sh",
      "${path.root}/scripts/05-install-custom-ca.sh",
      "${path.root}/scripts/10-install-docker.sh",
      "${path.root}/scripts/20-install-alloy.sh"
    ]
  }

  # --------------------------------------------------------
  # Disable Root login and IPv6
  # --------------------------------------------------------
  provisioner "shell" {
    environment_vars = [
      "DEFAULT_USER=${var.username}"
    ]
    execute_command = "sudo -E bash '{{ .Path }}'"
    scripts = [
      "${path.root}/scripts/80-disable-root-login.sh",
      "${path.root}/scripts/81-disable-ipv6.sh",
      "${path.root}/scripts/82-disable-cloudinit-updates.sh"
    ]
  }

  # --------------------------------------------------------
  # System verification before sealing
  # --------------------------------------------------------
  provisioner "shell" {
    execute_command = "sudo -E bash '{{ .Path }}'"
    scripts = [
      "${path.root}/scripts/90-verify-system.sh"
    ]
  }

  # --------------------------------------------------------
  # Final cleanup and sealing
  # --------------------------------------------------------
  provisioner "shell" {
    execute_command = "sudo -E bash '{{ .Path }}'"
    scripts = [
      "${path.root}/scripts/99-cleanup-seal.sh"
    ]
  }

  # --------------------------------------------------------
  # Manifest for metadata and CI integration
  # --------------------------------------------------------
  post-processor "manifest" {
    output = "manifest.json"
  }
}
