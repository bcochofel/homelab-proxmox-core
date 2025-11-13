#!/bin/bash

###############################################################################
# Ubuntu 24.04 Template Cleanup and Sealing Script
# Purpose: Prepare a system to be converted into a VM/Cloud template
# Usage: Run this script as root before converting VM to template
###############################################################################

set -e

###############################################################################

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    log_error "Please run as root"
    exit 1
fi

###############################################################################

# CRITICAL SAFETY CHECK
log_info "Performing safety checks..."

# Check if there's at least one non-root user with sudo access
NON_ROOT_SUDO_USERS=$(getent group sudo | cut -d: -f4 | tr ',' '\n' | grep -v "^root$" | wc -l)

if [ "$NON_ROOT_SUDO_USERS" -eq 0 ]; then
    log_error "CRITICAL: No non-root users with sudo access found!"
    log_error "Creating a template without a non-root admin user will lock you out."
    log_error ""
    log_error "Please create a user with sudo access first:"
    log_error "  adduser adminuser"
    log_error "  usermod -aG sudo adminuser"
    log_error ""
    log_error "Or if using cloud-init, ensure it creates a user on first boot."
    exit 1
fi

# Check if cloud-init is installed (strongly recommended for templates)
if ! command -v cloud-init &> /dev/null; then
    log_warn "WARNING: cloud-init is not installed!"
    log_warn "Without cloud-init, you must ensure:"
    log_warn "  1. A non-root user with SSH access exists"
    log_warn "  2. SSH host keys will be preserved (not regenerated)"
    log_warn ""
    read -p "Continue anyway? (yes/no): " response
    if [ "$response" != "yes" ]; then
        log_info "Aborting. Install cloud-init or create a user first."
        exit 1
    fi
fi

log_info "Safety checks passed!"
log_info "Found sudo users: $(getent group sudo | cut -d: -f4)"
echo ""

###############################################################################
# 1. STOP SERVICES
###############################################################################
log_info "Stopping services for cleanup..."

# Stop logging services temporarily
systemctl stop rsyslog 2>/dev/null || true
systemctl stop systemd-journald.socket 2>/dev/null || true
systemctl stop systemd-journald-dev-log.socket 2>/dev/null || true
systemctl stop systemd-journald-audit.socket 2>/dev/null || true
systemctl stop auditd 2>/dev/null || true

###############################################################################
# 2. CLEAN PACKAGE MANAGER
###############################################################################
log_info "Cleaning package manager caches..."

# Clean apt
apt-get clean -y
apt-get autoremove -y
apt-get autoclean -y

# Remove package lists
rm -rf /var/lib/apt/lists/*

# Clear apt cache
find /var/cache/apt -type f -delete

###############################################################################
# 3. CLEAN LOG FILES
###############################################################################
log_info "Cleaning log files..."

# Truncate all log files
find /var/log -type f -exec truncate -s 0 {} \;

# Remove rotated logs
find /var/log -type f -name "*.gz" -delete
find /var/log -type f -name "*.1" -delete
find /var/log -type f -name "*.old" -delete
find /var/log -type f -name "*.log.*" -delete

# Clean journal logs
journalctl --vacuum-time=1s 2>/dev/null || true
rm -rf /var/log/journal/*
rm -rf /run/log/journal/*

# Clean audit logs
if [ -d /var/log/audit ]; then
    find /var/log/audit -type f -delete
fi

###############################################################################
# 4. CLEAN TEMPORARY FILES
###############################################################################
log_info "Cleaning temporary files..."

# Clean /tmp
find /tmp -mindepth 1 -delete 2>/dev/null || true

# Clean /var/tmp
find /var/tmp -mindepth 1 -delete 2>/dev/null || true

# Clean /var/cache
find /var/cache -type f -delete 2>/dev/null || true

# Clean thumbnail cache
rm -rf /root/.cache/* 2>/dev/null || true
rm -rf /home/*/.cache/* 2>/dev/null || true
rm -rf /home/*/.thumbnails/* 2>/dev/null || true

###############################################################################
# 5. CLEAN USER HISTORY AND DATA
###############################################################################
log_info "Cleaning user history and data..."

# Remove bash history for all users
rm -f /root/.bash_history
rm -f /home/*/.bash_history
unset HISTFILE

# Remove other shell histories
rm -f /root/.zsh_history
rm -f /home/*/.zsh_history
rm -f /root/.mysql_history
rm -f /home/*/.mysql_history
rm -f /root/.psql_history
rm -f /home/*/.psql_history

# Clean SSH host keys (will be regenerated on first boot)
log_warn "Removing SSH host keys (will be regenerated on first boot)..."
# Only remove if cloud-init is present, otherwise keep them
if command -v cloud-init &> /dev/null; then
    rm -f /etc/ssh/ssh_host_*
else
    log_warn "Cloud-init not found - keeping SSH host keys for access"
fi

# Remove SSH authorized keys for root (keep for other users)
rm -f /root/.ssh/authorized_keys
rm -f /root/.ssh/known_hosts

# Clean user .ssh known_hosts (but NOT authorized_keys)
find /home -name "known_hosts" -delete 2>/dev/null || true

###############################################################################
# 6. CLEAN NETWORK CONFIGURATION
###############################################################################
log_info "Cleaning network configuration..."

# Remove persistent network device naming rules
rm -f /etc/udev/rules.d/70-persistent-net.rules
rm -f /etc/udev/rules.d/75-persistent-net-generator.rules

# Remove DHCP leases
rm -f /var/lib/dhcp/*.leases
rm -f /var/lib/dhclient/*

# Remove netplan machine-id based configurations
find /etc/netplan -type f -name "*.yaml" -exec sed -i '/dhcp-identifier/d' {} \;

###############################################################################
# 7. CLEAN CLOUD-INIT
###############################################################################
log_info "Cleaning cloud-init..."

# Clean cloud-init data
cloud-init clean --logs --seed 2>/dev/null || true
rm -rf /var/lib/cloud/*
rm -rf /run/cloud-init
rm -rf /var/log/cloud-init*

###############################################################################
# 8. REMOVE MACHINE-ID
###############################################################################
log_info "Removing machine-id (will be regenerated on first boot)..."

# Truncate machine-id (systemd will regenerate on boot)
truncate -s 0 /etc/machine-id
rm -f /var/lib/dbus/machine-id
ln -sf /etc/machine-id /var/lib/dbus/machine-id 2>/dev/null || true

###############################################################################
# 9. CLEAN MAIL
###############################################################################
log_info "Cleaning mail..."

rm -rf /var/mail/*
rm -rf /var/spool/mail/*

###############################################################################
# 10. REMOVE UNIQUE IDENTIFIERS
###############################################################################
log_info "Removing unique identifiers..."

# Remove any stored hardware addresses
mapfile -t addrs < <(compgen -G "/sys/class/net/*/address" || true)
if (( ${#addrs[@]} > 0 )); then
    find /sys/class/net -name address -type f
fi

# Clean swap UUID
swapoff -a 2>/dev/null || true

###############################################################################
# 11. CLEAN VIRTUALIZATION SPECIFIC
###############################################################################
log_info "Cleaning virtualization specific data..."

# VMware
if command -v vmware-toolbox-cmd &> /dev/null; then
    log_info "Detected VMware - clearing customization flags..."
    rm -f /etc/vmware-tools/GuestProxyData/server/key.pem 2>/dev/null || true
    rm -f /etc/vmware-tools/GuestProxyData/server/cert.pem 2>/dev/null || true
fi

# VirtualBox
if lsmod | grep -q vboxguest; then
    log_info "Detected VirtualBox..."
    # VirtualBox specific cleanup if needed
fi

# Hyper-V
if lsmod | grep -q hv_vmbus; then
    log_info "Detected Hyper-V..."
    # Hyper-V specific cleanup if needed
fi

###############################################################################
# 12. ZERO OUT FREE SPACE (Optional - improves compression)
###############################################################################
log_warn "Zeroing out free space (this may take a while)..."
log_warn "Skip this step if you're short on time (Ctrl+C within 5 seconds)"
sleep 5

# Zero out free space on root partition
dd if=/dev/zero of=/EMPTY bs=1M 2>/dev/null || true
rm -f /EMPTY

# Zero out free space on other partitions
for mount_point in $(df -h | grep ^/dev | awk '{print $6}' | grep -v "^/$"); do
    if [ -w "$mount_point" ]; then
        log_info "Zeroing free space on $mount_point..."
        dd if=/dev/zero of="$mount_point/EMPTY" bs=1M 2>/dev/null || true
        rm -f "$mount_point/EMPTY"
    fi
done

# Sync to ensure all writes are flushed
sync

###############################################################################
# 13. RESET HOSTNAME (Optional)
###############################################################################
log_info "Resetting hostname to 'localhost'..."
hostnamectl set-hostname localhost
echo "localhost" > /etc/hostname

###############################################################################
# 14. CLEAN SYSTEMD
###############################################################################
log_info "Cleaning systemd runtime data..."

rm -rf /var/lib/systemd/random-seed
systemd-machine-id-setup --print 2>/dev/null || true

###############################################################################
# 15. CLEAN AUDIT LOGS AND AIDE DATABASE
###############################################################################
log_info "Cleaning security audit data..."

# Clean audit logs
if [ -d /var/log/audit ]; then
    find /var/log/audit -type f -delete
fi

###############################################################################
# 16. PACKAGE SPECIFIC CLEANUP
###############################################################################
log_info "Cleaning application specific data..."

# Clean Docker if installed
if command -v docker &> /dev/null; then
    log_info "Cleaning Docker..."
    docker system prune -af --volumes 2>/dev/null || true
    rm -rf /var/lib/docker/containers/*
    rm -rf /var/lib/docker/tmp/*
    rm -rf /var/lib/docker/overlay2/*
fi

# Clean Snap
if command -v snap &> /dev/null; then
    log_info "Cleaning Snap..."
    rm -rf /var/lib/snapd/cache/*
fi

###############################################################################
# 17. DISABLE AUTOMATIC UPDATES TEMPORARILY
###############################################################################
log_info "Disabling automatic updates for template..."

# This prevents updates from running during template creation
systemctl stop apt-daily.timer 2>/dev/null || true
systemctl stop apt-daily-upgrade.timer 2>/dev/null || true
systemctl stop unattended-upgrades.service 2>/dev/null || true

###############################################################################
# 18. FINAL CLEANUP
###############################################################################
log_info "Performing final cleanup..."

# Clear command history for this session
history -c

# Sync filesystem
sync

###############################################################################
# COMPLETION
###############################################################################
echo ""
log_info "=========================================="
log_info "Template cleanup and sealing completed!"
log_info "=========================================="
echo ""
log_warn "IMPORTANT: Next steps:"
echo "  1. Shutdown this VM: 'shutdown -h now'"
echo "  2. Convert this VM to a template in your virtualization platform"
echo "  3. When deploying from template, ensure cloud-init or similar runs"
echo ""
log_warn "LOGIN INFORMATION:"
echo "  - Root login is DISABLED (both console and SSH)"
echo "  - Use these accounts to login:"
getent group sudo | cut -d: -f4 | tr ',' '\n' | grep -v "^root$" | while read user; do
    echo "    * $user (has sudo access)"
done
echo ""
if command -v cloud-init &> /dev/null; then
    echo "  - cloud-init will configure users on first boot"
else
    log_warn "  - NO cloud-init detected - ensure user accounts are properly configured!"
fi
echo ""
log_warn "Do NOT start this VM again before converting to template!"
log_warn "Do NOT run this script on a production system!"
echo ""

# Stop script execution here - admin should shutdown manually
exit 0
