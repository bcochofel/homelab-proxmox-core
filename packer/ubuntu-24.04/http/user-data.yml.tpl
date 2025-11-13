#cloud-config
autoinstall:
  version: 1

  # User Identity
  identity:
    hostname: ${hostname}
    username: ${username}
    password: ${password_hash}

  # Network
  network:
    version: 2
    ethernets:
      ens18: # Usual name for Proxmox using virtio driver
        dhcp4: true
        dhcp6: false  # Disable IPv6 DHCP

%{ if enable_proxy ~}
  proxy: ${proxy_url}
%{ endif ~}

  # SSH Configuration
  ssh:
    install-server: yes
    allow-pw: false
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

  # Packages
  packages:
%{ for package in packages ~}
    - ${package}
%{ endfor ~}

  # Late commands
  late-commands:
    # Disable IPv6
    - curtin in-target --target=/target -- sed -i 's/GRUB_CMDLINE_LINUX_DEFAULT=".*"/GRUB_CMDLINE_LINUX_DEFAULT="quiet splash ipv6.disable=1"/' /etc/default/grub
    - curtin in-target --target=/target -- update-grub

    # Disable root login
    - curtin in-target --target=/target -- passwd -l root
    - curtin in-target --target=/target -- usermod -s /usr/sbin/nologin root
    - curtin in-target --target=/target -- rm -f /root/.ssh/authorized_keys
    - curtin in-target --target=/target -- truncate -s 0 /etc/securetty

    # Enable qemu-guest-agent
    - curtin in-target --target=/target -- systemctl enable qemu-guest-agent

#    # Configure NTP with systemd-timesyncd
#    - |
#      cat > /target/etc/systemd/timesyncd.conf <<EOF
#      [Time]
#      NTP=${join(" ", ntp_servers)}
#      RootDistanceMaxSec=5
#      PollIntervalMinSec=32
#      PollIntervalMaxSec=2048
#      EOF
#    - curtin in-target --target=/target -- systemctl enable systemd-timesyncd

  # User data configuration
  user-data:
    # Timezone
    timezone: ${timezone}
    # Locale and Keyboard
    locale: ${locale}
    keyboard:
      layout: ${keyboard_layout}
      variant: ${keyboard_variant}
    # packages
    package_update: true
    package_upgrade: true
    manage_etc_hosts: true
    preserve_hostname: false
    # Regenerates SSH host keys
    ssh_deletekeys: true
    ssh_genkeytypes: ['rsa', 'ecdsa', 'ed25519']
    # disable root account
    disable_root: true
    # NTP Configuration
    ntp:
      enabled: true
      ntp_client: systemd-timesyncd
      servers:
%{ for server in ntp_servers ~}
        - ${server}
%{ endfor ~}
    users:
      - name: ${username}
        groups: [adm, cdrom, dip, plugdev, sudo, docker]
        shell: /bin/bash
        sudo: "ALL=(ALL) NOPASSWD:ALL"
        passwd: ${password_hash}
        lock_passwd: false
%{ if length(ssh_authorized_keys) > 0 ~}
        ssh_authorized_keys:
%{ for key in ssh_authorized_keys ~}
          - ${key}
%{ endfor ~}
%{ endif ~}
%{ if length(additional_users) > 0 ~}
      # Additional users
%{ for user in additional_users ~}
      - name: ${user.name}
        groups: ${jsonencode(user.groups)}
        shell: ${user.shell}
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

    write_files:
#      # Hardened SSH configuration
#      - path: /etc/ssh/sshd_config.d/99-hardening.conf
#        content: |
#          # Authentication
#          PermitRootLogin no
#          PubkeyAuthentication yes
#          PasswordAuthentication no
#          PermitEmptyPasswords no
#          ChallengeResponseAuthentication no
#          # Limit authentication attempts
#          MaxAuthTries 3
#          MaxSessions 2
#          # Disable unused authentication methods
#          KerberosAuthentication no
#          GSSAPIAuthentication no
#          # Protocol and encryption
#          Protocol 2
#          # Ciphers (strong only)
#          Ciphers chacha20-poly1305@openssh.com,aes256-gcm@openssh.com,aes128-gcm@openssh.com,aes256-ctr,aes192-ctr,aes128-ctr
#          # MACs (strong only)
#          MACs hmac-sha2-512-etm@openssh.com,hmac-sha2-256-etm@openssh.com,hmac-sha2-512,hmac-sha2-256
#          # Key exchange algorithms (strong only)
#          KexAlgorithms curve25519-sha256,curve25519-sha256@libssh.org,diffie-hellman-group16-sha512,diffie-hellman-group18-sha512,diffie-hellman-group-exchange-sha256
#          # Timeouts and keep-alive
#          ClientAliveInterval 300
#          ClientAliveCountMax 2
#          LoginGraceTime 60
#          # Logging
#          LogLevel VERBOSE
#          # Network
#          AddressFamily inet  # IPv4 only if you disabled IPv6
#          # Disable host-based authentication
#          HostbasedAuthentication no
#          IgnoreRhosts yes
#          # Banner (optional)
#          Banner /etc/ssh/banner
#
#      # SSH banner
#      - path: /etc/ssh/banner
#        content: |
#          ***************************************************************************
#                              AUTHORIZED ACCESS ONLY
#          Unauthorized access to this system is forbidden and will be
#          prosecuted by law. By accessing this system, you agree that your
#          actions may be monitored if unauthorized usage is suspected.
#          ***************************************************************************
#
#      # Automatic security updates
#      - path: /etc/apt/apt.conf.d/50unattended-upgrades
#        content: |
#          Unattended-Upgrade::Allowed-Origins {
#              "$$\{distro_id\}:$$\{distro_codename\}";
#              "$$\{distro_id\}:$$\{distro_codename\}-security";
#              "$$\{distro_id\}ESMApps:$$\{distro_codename\}-apps-security";
#              "$$\{distro_id\}ESM:$$\{distro_codename\}-infra-security";
#          };
#          Unattended-Upgrade::AutoFixInterruptedDpkg "true";
#          Unattended-Upgrade::MinimalSteps "true";
#          Unattended-Upgrade::Remove-Unused-Kernel-Packages "true";
#          Unattended-Upgrade::Remove-Unused-Dependencies "true";
#          Unattended-Upgrade::Automatic-Reboot "false";
#          Unattended-Upgrade::Automatic-Reboot-Time "03:00";
#          Unattended-Upgrade::SyslogEnable "true";
#
#      - path: /etc/apt/apt.conf.d/20auto-upgrades
#        content: |
#          APT::Periodic::Update-Package-Lists "1";
#          APT::Periodic::Download-Upgradeable-Packages "1";
#          APT::Periodic::AutocleanInterval "7";
#          APT::Periodic::Unattended-Upgrade "1";
#
#      # Login banner
#      - path: /etc/issue.net
#        content: |
#          ***************************************************************************
#                              AUTHORIZED ACCESS ONLY
#          Unauthorized access to this system is forbidden and will be
#          prosecuted by law. By accessing this system, you agree that your
#          actions may be monitored if unauthorized usage is suspected.
#          ***************************************************************************
#
      # Add to cron
      - path: /etc/cron.daily/security-audit
        content: |
          #!/bin/bash
          # Run security audit tools
          lynis audit system --quick
          rkhunter --check --skip-keypress
          aide --check

    runcmd:
#      # Set restrictive permissions on SSH config
#      - chmod 600 /etc/ssh/sshd_config.d/99-hardening.conf
#      # Restart SSH to apply changes
#      - systemctl restart sshd

      # Enable and start services
      - systemctl enable auditd
      - systemctl start auditd

      # Initialize AIDE (file integrity monitoring)
      - aideinit
      - mv /var/lib/aide/aide.db.new /var/lib/aide/aide.db

      # Set timezone
      - timedatectl set-timezone UTC

      # Enable NTP
      - timedatectl set-ntp true
