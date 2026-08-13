# ==========================================================
# Packer Template: Ubuntu 26.04 LTS (Proxmox ISO)
# Modular layout — variables and versions are in separate files.
# ==========================================================

source "proxmox-iso" "ubuntu-26-04" {
  # --------------------------------------------------------
  # Proxmox connection
  # --------------------------------------------------------
  proxmox_url              = var.proxmox_api_url
  username                 = var.proxmox_api_token_id
  token                    = var.proxmox_api_token_secret
  node                     = var.proxmox_node
  insecure_skip_tls_verify = var.proxmox_skip_tls_verify

  # --------------------------------------------------------
  # ISO Boot configuration
  # --------------------------------------------------------
  boot_iso {
    type     = var.boot_iso_type
    iso_file = var.boot_iso_file
    unmount  = var.boot_iso_unmount
  }

  # --------------------------------------------------------
  # Virtual Machine Settings
  # --------------------------------------------------------
  vm_id                = var.vm_id
  vm_name              = var.vm_name
  template_description = var.vm_description

  qemu_agent      = var.qemu_agent
  scsi_controller = var.scsi_controller

  disks {
    disk_size    = var.disk_size
    storage_pool = var.storage_pool
    type         = var.disk_type
    format       = "raw"
    io_thread    = true
    ssd          = true
    discard      = true
  }

  cores    = var.vm_cpu_cores
  sockets  = var.vm_cpu_sockets
  cpu_type = var.vm_cpu_type
  memory   = var.vm_memory

  network_adapters {
    model    = var.network_model
    bridge   = var.network_bridge
    firewall = false
  }

  # --------------------------------------------------------
  # Cloud-init and autoinstall
  # --------------------------------------------------------
  cloud_init              = false
  cloud_init_storage_pool = var.storage_pool

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
  ssh_username = var.username
  #ssh_password = var.password
  ssh_private_key_file = var.ssh_private_key_file
  # if ssh key has password use the agent
  #ssh_agent_auth = true
  ssh_timeout = var.ssh_timeout

  # --------------------------------------------------------
  # Define Tags
  # --------------------------------------------------------
  tags = var.tags
}

# ==========================================================
# Build configuration
# ==========================================================
build {
  name    = "ubuntu-26-04-core"
  sources = ["source.proxmox-iso.ubuntu-26-04"]

  # --------------------------------------------------------
  # Wait for cloud-init to complete (non-root safe)
  # --------------------------------------------------------
  provisioner "shell" {
    inline = [
      "echo 'Waiting for cloud-init to finish...'",
      "while [ ! -f /var/lib/cloud/instance/boot-finished ]; do echo 'Waiting for cloud-init...'; sleep 1; done",
      "sudo cloud-init status --wait || true",
      "sudo cloud-init status --long || true",
      "if sudo cloud-init status --long | grep -q 'errors: \\[\\]'; then echo 'cloud-init finished with no errors.'; else echo 'cloud-init reported errors, aborting.'; exit 1; fi"
    ]
    environment_vars = ["DEBIAN_FRONTEND=noninteractive"]
  }

  # -----------------------
  # Run provisioning scripts (as root) — environment variables exported here
  # -----------------------
  provisioner "shell" {
    environment_vars = [
      "INSTALL_DOCKER=${var.install_docker}"
    ]
    # `sudo -E` is rejected outright by this image's sudo policy ("preserving
    # the entire environment is not supported, '-E' is ignored"), so none of
    # environment_vars above ever reached any script that way. Passing
    # {{ .Vars }} as explicit VAR=value arguments directly to sudo (sudo's
    # native per-command env-setting syntax) works without needing -E at all.
    execute_command = "sudo {{ .Vars }} bash '{{ .Path }}'"
    # Use absolute paths under /tmp/scripts so it's clear where they run from
    # NN- prefixes are the provisioner order (see ADR-2): initrd network fix
    # first (no dependency on anything else), then Docker.
    scripts = [
      "${path.root}/scripts/15-fix-initrd-network.sh",
      "${path.root}/scripts/20-install-docker.sh"
    ]
  }

  # ------------------------------------------------------------
  # Run cleanup and seal the template
  # ------------------------------------------------------------
  provisioner "shell" {
    execute_command = "sudo -E bash '{{ .Path }}'"
    scripts = [
      "${path.root}/scripts/99-cleanup-seal.sh"
    ]
  }
}
