#!/usr/bin/env bash
set -euo pipefail
#
# Final cleanup and seal steps before shutting down the VM to become a template.
# IMPORTANT: this script will
#  - clean apt caches
#  - stop/kill lingering processes
#  - remove machine-specific data
#  - clear cloud-init runtime state (but NOT /etc/cloud/cloud.cfg.d/)
#  - zero-fill free space
#  - shutdown the VM
#

echo "==> Starting final cleanup and sealing..."

export DEBIAN_FRONTEND=noninteractive

# Update package metadata (quiet), apply housekeeping
apt-get update -qq || true

# Perform a safe upgrade if desired (optional). For maximum reproducibility you may
# prefer not to upgrade here; uncomment if you want the template to have latest security updates.
# apt-get -y upgrade || true

# Cleanup packages and caches
apt-get -y autoremove --purge || true
apt-get -y clean || true
rm -rf /var/lib/apt/lists/* || true

# Stop/kill package managers to avoid locks during zero-fill
set +e
pkill -9 -f apt || true
pkill -9 -f dpkg || true
pkill -9 -f unattended-upgrade || true
pkill -9 -f cloud-init || true
systemctl daemon-reexec || true
set -e

# Remove machine-specific identifiers and SSH host keys
rm -f /etc/ssh/ssh_host_* || true
truncate -s 0 /etc/machine-id || true
rm -f /var/lib/systemd/random-seed || true

# Clean logs & temp
find /var/log -type f -exec truncate -s 0 {} \; || true
rm -rf /tmp/* /var/tmp/* || true

# Cloud-init cleanup: remove runtime state and instance data
# This is required so clones start with a fresh cloud-init instance.
# It does not remove /etc/cloud/cloud.cfg.d/ (our static config), so it's safe for Proxmox.
echo "==> Cleaning cloud-init runtime state..."
if command -v cloud-init >/dev/null 2>&1; then
  cloud-init clean --logs --machine-id || true
fi

# Explicitly remove remaining runtime cloud-init directories (defensive)
rm -rf /var/lib/cloud/instances/* /var/lib/cloud/sem/* /var/lib/cloud/data/* /var/lib/cloud/seed/nocloud* || true

# Extra waiting to ensure services have settled
sync
sleep 2

# Zero-fill free space to make template compact
echo "==> Zero-filling free space (this may take a while)..."
set +e
dd if=/dev/zero of=/zerofile bs=1M status=progress 2>/dev/null || true
sync
rm -f /zerofile || true
set -e

# Final zombie check (log only)
ZOMBIES=$(ps -eo stat | grep -c Z || true)
echo "Zombie process count: ${ZOMBIES}"
if [[ "${ZOMBIES}" -gt 5 ]]; then
  echo "Warning: ${ZOMBIES} zombie processes remain."
fi

# Ensure all writebuffers are flushed
sync

echo "==> Cleanup complete. Shutting down now..."
# Final shutdown for Packer to pick up
#shutdown -h now
