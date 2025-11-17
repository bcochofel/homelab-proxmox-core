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

  # Storage
  storage:
    config:
      # Disk definition (match the biggest disk)
      - type: disk
        id: disk0
        match:
          largest: true
        ptable: gpt
        wipe: superblock-recursive
        preserve: false
        grub_device: true

      # BIOS boot partition
      - type: partition
        id: partition-bios
        device: disk0
        size: 1MB
        flag: bios_grub
        number: 1
        preserve: false
        grub_device: false

      # EFI partition
      - type: partition
        id: partition-efi
        device: disk0
        size: 512M
        flag: boot
        number: 2
        preserve: false
        grub_device: false

      - type: format
        id: format-efi
        volume: partition-efi
        fstype: fat32
        label: EFI

      - type: mount
        id: mount-efi
        device: format-efi
        path: /boot/efi

      # Boot partition
      - type: partition
        id: partition-boot
        device: disk0
        size: 1G
        number: 3
        preserve: false

      - type: format
        id: format-boot
        volume: partition-boot
        fstype: ext4
        label: BOOT

      - type: mount
        id: mount-boot
        device: format-boot
        path: /boot

      # LVM partition
      - type: partition
        id: partition-lvm
        device: disk0
        size: -1
        number: 4
        preserve: false

      # LVM Physical Volume
      - type: lvm_volgroup
        id: vg0
        name: ubuntu-vg
        devices:
          - partition-lvm

      # Root logical volume
      - type: lvm_partition
        id: lv-root
        volgroup: vg0
        name: root
        size: 25G

      - type: format
        id: format-root
        volume: lv-root
        fstype: ext4
        label: ROOT

      - type: mount
        id: mount-root
        device: format-root
        path: /

      # Home logical volume
      - type: lvm_partition
        id: lv-home
        volgroup: vg0
        name: home
        size: 5G

      - type: format
        id: format-home
        volume: lv-home
        fstype: ext4
        label: HOME

      - type: mount
        id: mount-home
        device: format-home
        path: /home
        options: nodev,nosuid

      # Tmp logical volume
      - type: lvm_partition
        id: lv-tmp
        volgroup: vg0
        name: tmp
        size: 5G

      - type: format
        id: format-tmp
        volume: lv-tmp
        fstype: ext4
        label: TMP

      - type: mount
        id: mount-tmp
        device: format-tmp
        path: /tmp
        options: nodev,nosuid

      # Opt logical volume
      - type: lvm_partition
        id: lv-opt
        volgroup: vg0
        name: opt
        size: -1

      - type: format
        id: format-opt
        volume: lv-opt
        fstype: ext4
        label: OPT

      - type: mount
        id: mount-opt
        device: format-opt
        path: /opt
        options: noatime,nodiratime

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

    # Fix fstab fsck pass numbers (only root should be 0 1, others should be 0 2)
    - curtin in-target --target=/target -- sed -i 's|\(/home.*\) 0 1|\1 0 2|' /etc/fstab
    - curtin in-target --target=/target -- sed -i 's|\(/tmp.*\) 0 1|\1 0 2|' /etc/fstab
    - curtin in-target --target=/target -- sed -i 's|\(/opt.*\) 0 1|\1 0 2|' /etc/fstab
    - curtin in-target --target=/target -- sed -i 's|\(/boot .*\) 0 1|\1 0 2|' /etc/fstab
    - curtin in-target --target=/target -- sed -i 's|\(/boot/efi.*\) 0 1|\1 0 2|' /etc/fstab

    # Install Docker prerequisites
    - curtin in-target --target=/target -- apt-get update
    - curtin in-target --target=/target -- apt-get install -y ca-certificates curl

    # Add Docker's official GPG key
    - curtin in-target --target=/target -- install -m 0755 -d /etc/apt/keyrings
    - curtin in-target --target=/target -- curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
    - curtin in-target --target=/target -- chmod a+r /etc/apt/keyrings/docker.asc

    # Add Docker repository (hardcoded for Ubuntu 24.04 Noble amd64)
    - curtin in-target --target=/target -- bash -c 'echo "deb [arch=amd64 signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu noble stable" > /etc/apt/sources.list.d/docker.list'

    # Install Docker
    - curtin in-target --target=/target -- apt-get update
    - curtin in-target --target=/target -- apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

    # Enable Docker service
    - curtin in-target --target=/target -- systemctl enable docker

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

      # rkhunter
      - path: /usr/lib/systemd/system/rkhunter.service
        content: |
          [Unit]
          Description=Run rkhunter scan

          [Service]
          Nice=15
          Type=simple
          ExecStart=/usr/bin/rkhunter --check --sk --quiet --logfile /var/log/rkhunter.log

      - path: /usr/lib/systemd/system/rkhunter.timer
        content: |
          [Unit]
          Description=Daily rkhunter scan

          [Timer]
          OnCalendar=daily
          RandomizedDelaySec=1800
          Persistent=false

          [Install]
          WantedBy=timers.target

      # AIDE configuration - exclude cloud-init and machine-specific files
      - path: /etc/aide/aide.conf.d/90_local_excludes
        content: |
          # Exclude cloud-init generated files
          !/var/lib/cloud
          !/var/log/cloud-init.log
          !/var/log/cloud-init-output.log

          # Exclude files that change per instance
          !/etc/machine-id
          !/etc/ssh/ssh_host_*
          !/var/lib/dbus/machine-id

          # Exclude log files that change frequently
          !/var/log/journal
          !/var/log/syslog
          !/var/log/auth.log
          !/var/log/rkhunter.log
          !/var/log/aide

      # AIDE initialization script
      - path: /usr/local/bin/initialize-aide.sh
        permissions: '0755'
        content: |
          #!/bin/bash
          set -euo pipefail

          AIDE_DB="/var/lib/aide/aide.db"
          AIDE_DB_NEW="/var/lib/aide/aide.db.new"
          AIDE_LOG="/var/log/aide/aide-init.log"

          # Create log directory if it doesn't exist
          mkdir -p /var/log/aide

          if [ -f "$AIDE_DB" ]; then
            echo "$(date): AIDE database already exists, skipping initialization" | tee -a "$AIDE_LOG"
            exit 0
          fi

          echo "$(date): Initializing AIDE database on first boot..." | tee -a "$AIDE_LOG"

          # Run aideinit
          if aideinit 2>&1 | tee -a "$AIDE_LOG"; then
            if [ -f "$AIDE_DB_NEW" ]; then
              cp "$AIDE_DB_NEW" "$AIDE_DB"
              echo "$(date): AIDE database initialized successfully" | tee -a "$AIDE_LOG"
              exit 0
            else
              echo "$(date): Error: AIDE database file not created" | tee -a "$AIDE_LOG"
              exit 1
            fi
          else
            echo "$(date): Error: aideinit command failed" | tee -a "$AIDE_LOG"
            exit 1
          fi

      # AIDE first-boot initialization service
      - path: /usr/lib/systemd/system/aide-init.service
        content: |
          [Unit]
          Description=Initialize AIDE database on first boot
          After=cloud-final.service
          ConditionPathExists=!/var/lib/aide/aide.db

          [Service]
          Type=oneshot
          ExecStart=/usr/local/bin/initialize-aide.sh
          RemainAfterExit=yes
          StandardOutput=journal
          StandardError=journal

          [Install]
          WantedBy=multi-user.target

      # AIDE regular check service
      - path: /usr/lib/systemd/system/aide-check.service
        content: |
          [Unit]
          Description=AIDE Integrity Check
          After=aide-init.service
          Requires=aide-init.service

          [Service]
          Type=oneshot
          ExecStart=/bin/bash -c '/usr/bin/aide --check 2>&1 | tee -a /var/log/aide/aide-check.log'

      # AIDE regular check timer
      - path: /usr/lib/systemd/system/aide-check.timer
        content: |
          [Unit]
          Description=AIDE Daily Integrity Check

          [Timer]
          OnCalendar=daily
          RandomizedDelaySec=1h
          Persistent=true

          [Install]
          WantedBy=timers.target

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

      # Set timezone
      - timedatectl set-timezone UTC

      # Enable NTP
      - timedatectl set-ntp true

      # Enable qemu-guest-agent
      - systemctl enable qemu-guest-agent

      # ===== SECURITY TOOLS CONFIGURATION =====

      # Reload systemd units after installing all custom services
      - systemctl daemon-reload

      # -----------------------------
      # Configure rkhunter
      # -----------------------------
      - rkhunter --update
      - rkhunter --propupd

      # -----------------------------
      # Configure AIDE
      # -----------------------------
      # Create AIDE log directory
      - mkdir -p /var/log/aide
