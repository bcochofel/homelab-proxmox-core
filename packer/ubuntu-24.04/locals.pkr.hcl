locals {
  # Timestamp for unique naming
  timestamp = regex_replace(timestamp(), "[- TZ:]", "")

  # Password hash (SHA-512)
  # Generate with: mkpasswd -m sha-512 yourpassword

  # Full hostname
  fqdn = "${var.hostname}.${var.domain}"

  # User data from template
  user_data = templatefile("${path.root}/http/user-data.yml.tpl", {
    username            = var.username
    password_hash       = var.password
    hostname            = var.hostname
    domain              = var.domain
    fqdn                = local.fqdn
    timezone            = var.timezone
    locale              = var.locale
    keyboard_layout     = var.keyboard_layout
    keyboard_variant    = var.keyboard_variant
    packages            = var.packages
    additional_users    = var.additional_users
    ssh_authorized_keys = var.ssh_authorized_keys
    ntp_servers         = var.ntp_servers
  })

  # Meta data (can also be templated if needed)
  meta_data = file("${path.root}/http/meta-data.yml")
}
