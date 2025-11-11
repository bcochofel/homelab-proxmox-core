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

  # Storage - Simple LVM with separated /opt and noatime attr
  storage:
    config:
      # Disk identification
      - type: disk
        id: disk0
        ptable: gpt
        wipe: superblock-recursive
        preserve: false
        grub_device: true
        match:
          size: largest

      # BIOS boot partition (for BIOS/legacy boot)
      - type: partition
        id: partition-bios
        device: disk0
        size: 1M
        flag: bios_grub
        number: 1

      # EFI partition (for UEFI boot)
      - type: partition
        id: partition-efi
        device: disk0
        size: 512M
        flag: boot
        number: 2

      # Boot partition
      - type: partition
        id: partition-boot
        device: disk0
        size: 1G
        number: 3

      # Root partition
      - type: partition
        id: partition-root
        device: disk0
        size: 20G
        number: 4

      # Swap partition
      - type: partition
        id: partition-swap
        device: disk0
        size: 2G
        number: 5

      # Opt partition (uses remaining space)
      - type: partition
        id: partition-opt
        device: disk0
        size: -1
        number: 6

      # Format EFI partition
      - type: format
        id: format-efi
        volume: partition-efi
        fstype: fat32
        label: EFI

      # Format boot partition
      - type: format
        id: format-boot
        volume: partition-boot
        fstype: ext4
        label: BOOT

      # Format root partition
      - type: format
        id: format-root
        volume: partition-root
        fstype: ext4
        label: ROOT

      # Format swap partition
      - type: format
        id: format-swap
        volume: partition-swap
        fstype: swap
        label: SWAP

      # Format opt partition
      - type: format
        id: format-opt
        volume: partition-opt
        fstype: ext4
        label: OPT

      # Mount EFI
      - type: mount
        id: mount-efi
        device: format-efi
        path: /boot/efi

      # Mount boot
      - type: mount
        id: mount-boot
        device: format-boot
        path: /boot

      # Mount root
      - type: mount
        id: mount-root
        device: format-root
        path: /

      # Mount swap
      - type: mount
        id: mount-swap
        device: format-swap
        path: none

      # Mount opt with noatime option
      - type: mount
        id: mount-opt
        device: format-opt
        path: /opt
        options: noatime

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
