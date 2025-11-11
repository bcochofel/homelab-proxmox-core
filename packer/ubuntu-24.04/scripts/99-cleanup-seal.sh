#!/usr/bin/env bash
set -euo pipefail
echo "==> Starting final cleanup and sealing..."

export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get -y upgrade
apt-get -y autoremove --purge
apt-get -y clean
rm -rf /var/lib/apt/lists/* || true

# Terminate lingering processes
pkill -9 -f apt || true
pkill -9 -f dpkg || true
pkill -9 -f cloud-init || true
pkill -9 -f unattended-upgrade || true
systemctl daemon-reexec || true

# Remove machine identifiers
rm -f /etc/ssh/ssh_host_* || true
truncate -s 0 /etc/machine-id || true
rm -f /var/lib/systemd/random-seed || true

# Clean logs and temp files
find /var/log -type f -exec truncate -s 0 {} \;
rm -rf /tmp/* /var/tmp/* || true

# Cloud-init cleanup
cloud-init clean --logs || true
rm -rf /var/lib/cloud/instances/* || true

# Zero-fill free space
set +e
dd if=/dev/zero of=/zerofile bs=1M status=progress 2>/dev/null || true
sync
rm -f /zerofile
set -e

# Zombie sanity check
ZOMBIES=$(ps -eo stat | grep -c Z || true)
echo "Zombie processes: ${ZOMBIES}"
if [[ "${ZOMBIES}" -gt 5 ]]; then
  echo "Warning: ${ZOMBIES} zombie processes remain."
fi

sync
#shutdown -h now
