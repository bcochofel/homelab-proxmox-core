#!/usr/bin/env bash
set -euo pipefail

_log() { echo "[$(date -Iseconds)] $*"; }

_log "==> Updating and upgrading packages..."
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get -y upgrade

_log "==> Clean apt cache..."
apt-get -y autoremove --purge
apt-get -y clean
rm -rf /var/lib/apt/lists/*

_log "Cleaning up system caches and logs..."

# Clean cloud-init
cloud-init clean
rm -f /etc/cloud/cloud.cfg.d/99-installer.cfg
rm -f /etc/cloud/cloud.cfg.d/subiquity-disable-cloudinit-networking.cfg

# Remove temporary files
rm -rf /tmp/* /var/tmp/*

_log "==> Killing leftover or defunct processes..."
set +e
pkill -9 -f apt || true
pkill -9 -f dpkg || true
pkill -9 -f cloud-init || true
# force systemd to reap zombies
systemctl daemon-reexec
set -e

# Remove SSH host keys, machine IDs, and random seeds
rm -f /etc/ssh/ssh_host_* /etc/machine-id /var/lib/dbus/machine-id || true
rm -f /var/log/wtmp /var/log/btmp || true

# Clean log files (truncate but keep structure)
find /var/log -type f -exec truncate -s 0 {} \;

# Remove machine ID (for cloned VMs)
truncate -s 0 /etc/machine-id || true
rm -f /var/lib/dbus/machine-id
ln -s /etc/machine-id /var/lib/dbus/machine-id

# Zero-fill free space to make image smaller
if command -v dd >/dev/null 2>&1; then
  _log "Zero-filling free space to reduce image size..."
  set +e
  dd if=/dev/zero of=/zerofile bs=1M status=progress 2>/dev/null || true
  sync
  rm -f /zerofile
  set -e
  _log "Zero-fill complete."
fi

sync

_log "System cleanup complete."
