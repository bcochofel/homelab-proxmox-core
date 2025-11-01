source "proxmox-iso" "ubuntu2404" {

  # Proxmox Connection Settings
  proxmox_url = var.pm_api_url
  username    = var.pm_api_token_id
  token       = var.pm_api_token_secret

  insecure_skip_tls_verify = true

  # VM ID/name
  vm_id                = 5002
  vm_name              = "ubuntu-2404-tmpl"
  template_description = "Ubuntu 24.04 Server Image"

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

  #  # Packer Autoinstall Settings
  #  http_content = {
  #    "user-data" = templatefile(abspath("${path.root}/http/user-data.tmpl"), {
  #      locale              = var.locale
  #      keyboard_layout     = var.keyboard_layout
  #      keyboard_variant    = var.keyboard_variant
  #      hostname            = var.hostname
  #      timezone            = var.timezone
  #      users               = var.users
  #      packages            = var.packages
  #      ssh_authorized_keys = var.ssh_authorized_keys
  #      storage_config      = var.storage_config
  #    })
  #    "meta-data" = file(abspath("${path.root}/http/meta-data"))
  #  }
  http_directory = "${path.root}/http"
  http_interface = "eth0"

  # Packer SSH Settings
  ssh_username         = var.ssh_username
  ssh_private_key_file = var.ssh_private_key_file
  # if ssh key has password use the agent
  #ssh_agent_auth = true

  # Raise the timeout, when installation takes longer
  ssh_timeout = "20m"

  # Set tags
  tags = "${var.tags};noble"
}

build {
  name    = "ubuntu-2404-template"
  sources = ["source.proxmox-iso.ubuntu2404"]

  # Conditional proxy setup
  provisioner "shell" {
    execute_command = "sudo bash '{{ .Path }}'"
    scripts = [
      abspath("${path.root}/scripts/01_configure_proxy.sh"),
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
      abspath("${path.root}/scripts/02_install_docker.sh"),
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
      abspath("${path.root}/scripts/03_install_alloy.sh"),
    ]
    environment_vars = [
      "USE_ALLOY=${var.use_alloy}",
      "PROM_ENDPOINTS=${join(",", var.prometheus_endpoints)}",
      "LOKI_ENDPOINTS=${join(",", var.loki_endpoints)}",
      "ALLOY_VERSION=${var.alloy_version}"
    ]
  }

  # qemu-agent provisioning script
  provisioner "shell" {
    execute_command = "sudo bash '{{ .Path }}'"
    scripts = [
      abspath("${path.root}/scripts/04_enable_qemu_agent.sh"),
    ]
  }

  # Finalize / Unseal the image
  provisioner "shell" {
    execute_command = "sudo bash '{{ .Path }}'"
    scripts = [
      abspath("${path.root}/scripts/05_seal_template.sh"),
    ]
  }
}
