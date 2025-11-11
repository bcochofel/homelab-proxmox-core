#!/usr/bin/env bash
set -euo pipefail

DEF_USER=${DEFAULT_USER:-ubuntu}

echo "==> Disabling root login and locking root account..."

# Lock root user
passwd -l root || true

# Remove root password if still set
usermod -p '*' root || true

echo "==> Enabling ${DEF_USER} for console login..."

# Unlock default user for console logins only
if passwd -S ${DEF_USER} | grep -q 'L'; then
  echo "==> Unlocking ${DEF_USER} user for console login..."
  passwd -u ${DEF_USER} || true
  usermod -U ${DEF_USER} || true
fi

# Disable SSH root login explicitly
sed -i 's/^#*PermitRootLogin.*/PermitRootLogin no/' /etc/ssh/sshd_config
sed -i 's/^#*PasswordAuthentication.*/PasswordAuthentication no/' /etc/ssh/sshd_config
sed -i 's/^#*PermitEmptyPasswords.*/PermitEmptyPasswords no/' /etc/ssh/sshd_config

systemctl reload ssh || true

echo "==> Root login fully disabled (SSH and local)."
