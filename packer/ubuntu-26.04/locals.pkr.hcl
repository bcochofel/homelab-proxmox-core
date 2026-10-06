locals {
  # Timestamp for unique naming
  timestamp = regex_replace(timestamp(), "[- TZ:]", "")

  # Static build network (ADR-4). The installer's kernel `ip=` parameter
  # (`<ip>::<gateway>:<netmask>:<hostname>:<device>:none:<dns0>:<dns1>`)
  # brings the NIC up before the autoinstall config is fetched; user-data's
  # `network` section keeps the same address for the rest of the build.
  build_interface = "ens18" # Proxmox's name for the first virtio NIC
  build_ip        = split("/", var.build_ip_cidr)[0]
  build_kernel_ip = join(":", concat([
    local.build_ip, "", var.build_gateway, cidrnetmask(var.build_ip_cidr),
    var.hostname, local.build_interface, "none",
  ], var.build_nameservers))

  # User data from template
  user_data = templatefile("${path.root}/http/user-data.yml.tpl", {
    username            = var.username
    password_hash       = var.password_hash
    hostname            = var.hostname
    timezone            = var.timezone
    locale              = var.locale
    keyboard_layout     = var.keyboard_layout
    keyboard_variant    = var.keyboard_variant
    packages            = var.packages
    additional_users    = var.additional_users
    ssh_authorized_keys = var.ssh_authorized_keys
    ntp_servers         = var.ntp_servers
    build_interface     = local.build_interface
    build_ip_cidr       = var.build_ip_cidr
    build_gateway       = var.build_gateway
    build_nameservers   = var.build_nameservers
  })

  # Meta data (can also be templated if needed)
  meta_data = file("${path.root}/http/meta-data.yml")
}
