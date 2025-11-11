#!/usr/bin/env bash
set -euo pipefail
#
# Disable cloud-init automatic package updates/upgrades in a permanent,
# filesystem-backed (non-runtime) way that is safe for Proxmox templates.
#
# This script:
#  - writes /etc/cloud/cloud.cfg.d/99-disable-updates.cfg (static)
#  - writes /etc/apt/apt.conf.d/10disable-periodic to disable apt timers
#  - DOES NOT run cloud-init modules or touch /var/lib/cloud/seed (avoids checksum mismatch)
#

echo "==> Disabling cloud-init automatic package updates (static config)"

# Ensure dir exists
mkdir -p /etc/cloud/cloud.cfg.d

# Create persistent cloud-init config to disable package updates
cat > /etc/cloud/cloud.cfg.d/99-disable-updates.cfg <<'EOF'
# Disable automatic apt operations performed by cloud-init
package_update: false
package_upgrade: false
package_reboot_if_required: false
EOF

chmod 0644 /etc/cloud/cloud.cfg.d/99-disable-updates.cfg
echo "Wrote /etc/cloud/cloud.cfg.d/99-disable-updates.cfg"

# Also disable periodic apt activities (apt-daily)
# This stops automatic apt periodic tasks (update/upgrade) at the apt level.
cat > /etc/apt/apt.conf.d/10disable-periodic <<'EOF'
APT::Periodic::Enable "0";
APT::Periodic::Update-Package-Lists "0";
APT::Periodic::Download-Upgradeable-Packages "0";
APT::Periodic::AutocleanInterval "0";
APT::Periodic::Unattended-Upgrade "0";
EOF

chmod 0644 /etc/apt/apt.conf.d/10disable-periodic
echo "Wrote /etc/apt/apt.conf.d/10disable-periodic to disable apt periodic tasks"

# Optionally mask apt timers (defensive, but safe in image build)
if command -v systemctl >/dev/null 2>&1; then
  systemctl mask --now apt-daily.timer apt-daily-upgrade.timer >/dev/null 2>&1 || true
  # also mask unattended-upgrades if present (keeps package installed but not auto-run)
  systemctl disable --now unattended-upgrades.service >/dev/null 2>&1 || true
fi

echo "==> Cloud-init update/upgrade automation disabled (static)."
