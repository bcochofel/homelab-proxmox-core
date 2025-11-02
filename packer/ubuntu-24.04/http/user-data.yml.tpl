#cloud-config
autoinstall:
  version: 1

  # Locale and Keyboard
  locale: ${locale}
  keyboard:
    layout: ${keyboard_layout}
    variant: ${keyboard_variant}

  # User Identity
  disable-root-login: true
  identity:
    hostname: ${hostname}
    username: ${username}
    password: ${password_hash}

  # SSH Configuration
  ssh:
    install-server: yes
    password-authentication: false
    allow-pw: false
    disable-root: true
    allow_public_ssh_keys: true
%{ if length(ssh_authorized_keys) > 0 ~}
    authorized-keys:
%{ for key in ssh_authorized_keys ~}
      - ${key}
%{ endfor ~}
%{ endif ~}

  # Storage - Simple LVM
  storage:
    layout:
      name: lvm
      sizing-policy: all
      reset-partition: true

  # Network
  network:
    version: 2
    ethernets:
      ens18:
        dhcp4: true
        dhcp-identifier: mac
#        disable-ipv6: true

  # Timezone
  timezone: ${timezone}

  # Packages
  packages:
%{ for package in packages ~}
    - ${package}
%{ endfor ~}

  # Package updates
  package_update: true
  package_upgrade: true

  # User data configuration
  user-data:
    fqdn: ${fqdn}
    manage_etc_hosts: true
    preserve_hostname: false

    # NTP Configuration
    ntp:
      enabled: true
      ntp_client: systemd-timesyncd
      servers:
%{ for server in ntp_servers ~}
        - ${server}
%{ endfor ~}

%{ if length(additional_users) > 0 ~}
    # Additional users
    users:
      - name: ${username}
        groups: [adm, cdrom, dip, plugdev, sudo, docker]
        shell: /bin/bash
        sudo: "ALL=(ALL) NOPASSWD:ALL"
        lock_passwd: false
%{ if length(ssh_authorized_keys) > 0 ~}
        ssh_authorized_keys:
%{ for key in ssh_authorized_keys ~}
          - ${key}
%{ endfor ~}
%{ endif ~}
%{ for user in additional_users ~}
      - name: ${user.name}
        groups: ${jsonencode(user.groups)}
        shell: /bin/bash
        sudo: ${user.sudo}
%{ if length(user.ssh_authorized_keys) > 0 ~}
        ssh_authorized_keys:
%{ for key in ssh_authorized_keys ~}
          - ${key}
%{ endfor ~}
%{ endif ~}
        lock_passwd: ${user.lock_passwd}
%{ endfor ~}
%{ endif ~}

  # Late commands
  late-commands:
    # Configure sudoers
    - echo '${username} ALL=(ALL) NOPASSWD:ALL' > /target/etc/sudoers.d/${username}
    - curtin in-target --target=/target -- chmod 440 /etc/sudoers.d/${username}

    # Enable qemu-guest-agent
    - curtin in-target --target=/target -- systemctl enable qemu-guest-agent

    # Set correct locale
    - curtin in-target --target=/target -- locale-gen ${locale}
    - curtin in-target --target=/target -- update-locale LANG=${locale}

    # Set timezone
    - curtin in-target --target=/target -- timedatectl set-timezone ${timezone}

    # Configure NTP with systemd-timesyncd
    - |
      cat > /target/etc/systemd/timesyncd.conf <<EOF
      [Time]
      NTP=${join(" ", ntp_servers)}
      RootDistanceMaxSec=5
      PollIntervalMinSec=32
      PollIntervalMaxSec=2048
      EOF

    # Enable and start systemd-timesyncd
    - curtin in-target --target=/target -- systemctl enable systemd-timesyncd
    - curtin in-target --target=/target -- systemctl start systemd-timesyncd

    # Final update
    - curtin in-target --target=/target -- apt-get update
    - curtin in-target --target=/target -- apt-get upgrade -y
