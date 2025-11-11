#!/usr/bin/env bash
set -euo pipefail
echo "==> Disabling IPv6 system-wide..."

# Disable IPv6 immediately and persistently
cat > /etc/sysctl.d/99-disable-ipv6.conf <<EOF
net.ipv6.conf.all.disable_ipv6 = 1
net.ipv6.conf.default.disable_ipv6 = 1
net.ipv6.conf.lo.disable_ipv6 = 1
EOF

sysctl -p /etc/sysctl.d/99-disable-ipv6.conf || true

# Optional: disable IPv6 in GRUB (for kernel level)
if grep -q "GRUB_CMDLINE_LINUX" /etc/default/grub; then
  sed -i 's/^GRUB_CMDLINE_LINUX=.*/GRUB_CMDLINE_LINUX="ipv6.disable=1"/' /etc/default/grub
  update-grub || true
fi

echo "==> IPv6 disabled successfully."
