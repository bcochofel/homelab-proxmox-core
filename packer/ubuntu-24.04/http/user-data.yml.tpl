#cloud-config
autoinstall:
  version: 1

  # User Identity
  identity:
    hostname: ${hostname}
    username: ${username}
    password: '${password_hash}'

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
      #############################################
      # Select largest disk (your 60GB disk)
      #############################################
      - type: disk
        id: disk0
        match:
          largest: true
        ptable: gpt
        wipe: superblock-recursive
        grub_device: true

      #############################################
      # EFI partition
      #############################################
      - type: partition
        id: part-efi
        device: disk0
        size: 550M
        flag: boot

      #############################################
      # LVM physical volume partition (rest of disk)
      #############################################
      - type: partition
        id: part-pv
        device: disk0
        size: -1

      #############################################
      # LVM PV and VG
      #############################################
      - type: lvm_pv
        id: pv0
        device: part-pv

      - type: lvm_vg
        id: vg0
        name: vg0
        devices:
          - pv0

      #############################################
      # ROOT LV (15 GB)
      #############################################
      - type: lvm_lv
        id: lv-root
        name: root
        vg: vg0
        size: 15G

      - type: format
        id: fmt-root
        volume: lv-root
        fstype: xfs

      - type: mount
        id: mount-root
        device: fmt-root
        path: /
        options: "noatime"

      #############################################
      # OPT LV (38 GB)
      #############################################
      - type: lvm_lv
        id: lv-opt
        name: opt
        vg: vg0
        size: 38G

      - type: format
        id: fmt-opt
        volume: lv-opt
        fstype: xfs

      - type: mount
        id: mount-opt
        device: fmt-opt
        path: /opt
        options: "noatime"

      #############################################
      # HOME LV (2 GB)
      #############################################
      - type: lvm_lv
        id: lv-home
        name: home
        vg: vg0
        size: 2G

      - type: format
        id: fmt-home
        volume: lv-home
        fstype: xfs

      - type: mount
        id: mount-home
        device: fmt-home
        path: /home
        options: "noatime,nodev"

      #############################################
      # TMP LV (4 GB) – secure mount flags
      #############################################
      - type: lvm_lv
        id: lv-tmp
        name: tmp
        vg: vg0
        size: 4G

      - type: format
        id: fmt-tmp
        volume: lv-tmp
        fstype: xfs

      - type: mount
        id: mount-tmp
        device: fmt-tmp
        path: /tmp
        # Additional secure mount flags applied at boot
        options: "noatime,nodev,nosuid,noexec"

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

    # SWAP file
    - curtin in-target --target=/target -- fallocate -l 4G /swapfile
    - curtin in-target --target=/target -- chmod 600 /swapfile
    - curtin in-target --target=/target -- mkswap /swapfile
    - curtin in-target --target=/target -- echo '/swapfile none swap sw 0 0' >> /etc/fstab
    - curtin in-target --target=/target -- swapon -a

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
    ssh_quiet_keygen: false
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
        sudo: 'ALL=(ALL) NOPASSWD:ALL'
        passwd: '${password_hash}'
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
        lock_passwd: ${user.lock_passwd}
%{ if length(user.ssh_authorized_keys) > 0 ~}
        ssh_authorized_keys:
%{ for key in ssh_authorized_keys ~}
          - ${key}
%{ endfor ~}
%{ endif ~}
%{ endfor ~}
%{ endif ~}

    write_files:
      # sysctl for swap
      - path: /etc/sysctl.d/80-swap-tuning.conf
        content: |
          # Keep swap usage minimal — only under pressure
          vm.swappiness = 10

          # Strongly prefer keeping application memory in RAM
          vm.vfs_cache_pressure = 50

          # Reduce tendency to reclaim small anonymous memory pages
          vm.page-cluster = 0

          # Avoid full inactive page scans (helps on virtualized systems)
          vm.watermark_scale_factor = 100

          # Improve responsiveness under memory load
          vm.dirty_ratio = 10
          vm.dirty_background_ratio = 5

          # Improve I/O behavior (especially on SSD-backed storage)
          vm.dirty_writeback_centisecs = 1500

      # Hardened SSH configuration
      - path: /etc/ssh/sshd_config.d/99-hardening.conf
        content: |
          # Authentication
          PermitRootLogin no
          PubkeyAuthentication yes
          PasswordAuthentication no
          PermitEmptyPasswords no
          # Limit authentication attempts
          MaxAuthTries 3
          MaxSessions 2
          # Protocol and encryption
          Protocol 2
          # Ciphers (strong only)
          Ciphers chacha20-poly1305@openssh.com,aes256-gcm@openssh.com,aes128-gcm@openssh.com,aes256-ctr,aes192-ctr,aes128-ctr
          # MACs (strong only)
          MACs hmac-sha2-512-etm@openssh.com,hmac-sha2-256-etm@openssh.com,hmac-sha2-512,hmac-sha2-256
          # Key exchange algorithms (strong only)
          KexAlgorithms curve25519-sha256,curve25519-sha256@libssh.org,diffie-hellman-group16-sha512,diffie-hellman-group18-sha512,diffie-hellman-group-exchange-sha256
          # Logging
          LogLevel VERBOSE
          # Network
          AddressFamily inet  # IPv4 only if you disabled IPv6
          # Banner (optional)
          Banner /etc/ssh/banner

      # SSH banner
      - path: /etc/ssh/banner
        content: |
          ***************************************************************************
                              AUTHORIZED ACCESS ONLY
          Unauthorized access to this system is forbidden and will be
          prosecuted by law. By accessing this system, you agree that your
          actions may be monitored if unauthorized usage is suspected.
          ***************************************************************************

      # Automatic security updates
      - path: /etc/apt/apt.conf.d/50unattended-upgrades
        content: |
          Unattended-Upgrade::Allowed-Origins {
              "$$\{distro_id\}:$$\{distro_codename\}";
              "$$\{distro_id\}:$$\{distro_codename\}-security";
              "$$\{distro_id\}ESMApps:$$\{distro_codename\}-apps-security";
              "$$\{distro_id\}ESM:$$\{distro_codename\}-infra-security";
          };
          Unattended-Upgrade::AutoFixInterruptedDpkg "true";
          Unattended-Upgrade::MinimalSteps "true";
          Unattended-Upgrade::Remove-Unused-Kernel-Packages "true";
          Unattended-Upgrade::Remove-Unused-Dependencies "true";
          Unattended-Upgrade::Automatic-Reboot "false";
          Unattended-Upgrade::Automatic-Reboot-Time "03:00";
          Unattended-Upgrade::SyslogEnable "true";

      - path: /etc/apt/apt.conf.d/20auto-upgrades
        content: |
          APT::Periodic::Update-Package-Lists "1";
          APT::Periodic::Download-Upgradeable-Packages "1";
          APT::Periodic::AutocleanInterval "7";
          APT::Periodic::Unattended-Upgrade "1";

      # Login banner
      - path: /etc/issue.net
        content: |
          ***************************************************************************
                              AUTHORIZED ACCESS ONLY
          Unauthorized access to this system is forbidden and will be
          prosecuted by law. By accessing this system, you agree that your
          actions may be monitored if unauthorized usage is suspected.
          ***************************************************************************

      # Add to cron
      - path: /etc/cron.daily/security-audit
        content: |
          #!/bin/bash
          # Run security audit tools
          aide --check
          lynis audit system --quick
          rkhunter --check --skip-keypress

    runcmd:
      # Disable root login
      - passwd -l root
      - usermod -s /usr/sbin/nologin root

      # Set restrictive permissions on SSH config
      - chmod 600 /etc/ssh/sshd_config.d/99-hardening.conf
      # Restart SSH to apply changes
      - systemctl restart sshd

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

      # Enable qemu-guest-agent
      - systemctl enable qemu-guest-agent
