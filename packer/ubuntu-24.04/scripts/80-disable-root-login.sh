#!/usr/bin/env bash
set -euo pipefail
echo "==> Disabling root login and locking root account..."

# Lock root user
passwd -l root || true

# Remove root password if still set
usermod -p '*' root || true

# Disable SSH root login explicitly
sed -i 's/^#*PermitRootLogin.*/PermitRootLogin no/' /etc/ssh/sshd_config
sed -i 's/^#*PasswordAuthentication.*/PasswordAuthentication no/' /etc/ssh/sshd_config
sed -i 's/^#*PermitEmptyPasswords.*/PermitEmptyPasswords no/' /etc/ssh/sshd_config

systemctl reload ssh || true

echo "==> Root login fully disabled (SSH and local)."
