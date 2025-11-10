#!/usr/bin/env bash
set -euo pipefail

_log() { echo "[$(date -Iseconds)] $*"; }

_log "Cleaning up system caches and logs..."

# Clean APT cache
sudo apt-get autoremove -y
sudo apt-get clean -y
sudo rm -rf /var/lib/apt/lists/*

# Clean cloud-init
sudo cloud-init clean
sudo rm -f /etc/cloud/cloud.cfg.d/99-installer.cfg
sudo rm -f /etc/cloud/cloud.cfg.d/subiquity-disable-cloudinit-networking.cfg

# Remove temporary files
sudo rm -rf /tmp/* /var/tmp/*

# Remove SSH host keys, machine IDs, and random seeds
sudo rm -f /etc/ssh/ssh_host_* /etc/machine-id /var/lib/dbus/machine-id || true
sudo rm -f /var/log/wtmp /var/log/btmp || true

# Clean log files (truncate but keep structure)
sudo find /var/log -type f -exec truncate -s 0 {} \;

# Remove machine ID (for cloned VMs)
sudo truncate -s 0 /etc/machine-id || true
sudo rm -f /var/lib/dbus/machine-id
sudo ln -s /etc/machine-id /var/lib/dbus/machine-id

# Zero-fill free space to make image smaller
if command -v dd >/dev/null 2>&1; then
  sudo dd if=/dev/zero of=/zerofile bs=1M || true
  sudo rm -f /zerofile
fi

sudo sync

_log "System cleanup complete."
