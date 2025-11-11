#!/usr/bin/env bash
set -euo pipefail
LOGFILE="/var/log/image-verify.log"
exec > >(tee -a "$LOGFILE") 2>&1

echo "==> Running verification checks (services, NTP, storage, hardening, zombies)"

# Timesyncd
if systemctl is-active --quiet systemd-timesyncd; then
  echo "✔ systemd-timesyncd active"
else
  echo "❌ systemd-timesyncd inactive" >&2
  exit 1
fi

# NTP sync
if timedatectl show | grep -q 'NTPSynchronized=yes'; then
  echo "✔ NTP synchronized"
else
  echo "❌ NTP not synchronized" >&2
  timedatectl show
  exit 1
fi

# QEMU guest agent
systemctl is-active --quiet qemu-guest-agent && echo "✔ qemu-guest-agent active" || (echo "❌ qemu-guest-agent inactive" >&2; exit 1)

# Docker
if command -v docker >/dev/null 2>&1; then
  systemctl is-active --quiet docker && echo "✔ Docker active" || (echo "❌ Docker inactive" >&2; exit 1)
else
  echo "ℹ Docker not installed"
fi

# Grafana Alloy
if systemctl list-unit-files | grep -q alloy.service; then
  systemctl is-active --quiet alloy && echo "✔ Alloy active" || (echo "❌ Alloy inactive" >&2; exit 1)
else
  echo "ℹ Grafana Alloy unit not found"
fi

# SSH hardening
grep -q '^PermitRootLogin no' /etc/ssh/sshd_config && echo "✔ SSH root login disabled" || (echo "❌ SSH root login not disabled" >&2; exit 1)
grep -q '^PasswordAuthentication no' /etc/ssh/sshd_config && echo "✔ SSH password auth disabled" || (echo "❌ SSH password auth not disabled" >&2; exit 1)

# Storage / LVM
echo "==> Checking storage layout..."
lsblk -o NAME,FSTYPE,SIZE,MOUNTPOINT,LABEL || true
vgs || echo "ℹ No LVM volume groups found"
lvs || echo "ℹ No LVM logical volumes found"
df -hT || true
mount | grep -E '^/dev' || true

# Zombies
ZOMBIES=$(ps -eo stat | grep -c Z || true)
echo "Zombie process count: ${ZOMBIES}"
if [[ "${ZOMBIES}" -gt 10 ]]; then
  echo "❌ Too many zombie processes" >&2
  exit 1
fi

echo "==> Verification successful."
