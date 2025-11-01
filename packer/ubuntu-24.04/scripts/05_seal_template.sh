#!/bin/bash
set -e
echo "=== Sealing Ubuntu 24.04 template ==="

# Stop services
systemctl stop rsyslog || true
systemctl stop systemd-journald || true

# Clear logs
echo "Clearing logs..."
truncate -s0 /var/log/wtmp || true
truncate -s0 /var/log/btmp || true
find /var/log -type f -exec truncate -s0 {} \;

# Remove temporary files
echo "Cleaning /tmp and apt cache..."
rm -rf /tmp/* /var/tmp/* /var/lib/apt/lists/*

# Remove SSH host keys
echo "Removing old SSH host keys..."
rm -f /etc/ssh/ssh_host_*

# Clean shell history
echo "Removing shell history..."
unset HISTFILE
rm -f /root/.bash_history /home/*/.bash_history

# Clean machine ID
echo "Resetting machine-id..."
truncate -s 0 /etc/machine-id
ln -sf /etc/machine-id /var/lib/dbus/machine-id

# Clean netplan persistent files
echo "Removing netplan persistent rules..."
rm -f /etc/netplan/*.bak /etc/udev/rules.d/70-persistent-net.rules || true

# Reset cloud-init
echo "Cleaning cloud-init state..."
cloud-init clean --logs

# Re-enable journald
systemctl start systemd-journald

echo "Template seal complete."
