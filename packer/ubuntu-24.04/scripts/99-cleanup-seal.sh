#!/bin/bash

###############################################################################
# Ubuntu 24.04 Minimal Template Cleanup Script
# Purpose: Clean template - cloud-init handles the rest
# Usage: Run as root before converting to template
#
# Assumes: cloud-init is installed and will handle initialization
###############################################################################

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

if [ "$EUID" -ne 0 ]; then
    log_error "Please run as root"
    exit 1
fi

###############################################################################
# SAFETY CHECK
###############################################################################
log_info "Checking for non-root sudo users..."
NON_ROOT_SUDO_USERS=$(getent group sudo | cut -d: -f4 | tr ',' '\n' | grep -v "^root$" | wc -l)

if [ "$NON_ROOT_SUDO_USERS" -eq 0 ]; then
    log_error "No non-root sudo users found! This will lock you out."
    log_error "Create a user first: adduser <username> && usermod -aG sudo <username>"
    exit 1
fi

if ! command -v cloud-init &> /dev/null; then
    log_warn "cloud-init not found! Ensure you have another way to initialize VMs"
    read -p "Continue anyway? (yes/no): " response
    [ "$response" != "yes" ] && exit 1
fi

log_info "Starting minimal template cleanup..."

###############################################################################
# 1. STOP LOGGING TEMPORARILY
###############################################################################
systemctl stop rsyslog 2>/dev/null || true

###############################################################################
# 2. PACKAGE CLEANUP
###############################################################################
log_info "Cleaning packages..."
apt-get clean -y
apt-get autoremove -y
rm -rf /var/lib/apt/lists/*
rm -rf /var/cache/apt/*

###############################################################################
# 3. LOG CLEANUP
###############################################################################
log_info "Cleaning logs..."
find /var/log -type f -exec truncate -s 0 {} \;
find /var/log -type f \( -name "*.gz" -o -name "*.1" -o -name "*.old" \) -delete
journalctl --vacuum-time=1s 2>/dev/null || true
rm -rf /var/log/journal/* 2>/dev/null || true

###############################################################################
# 4. TEMPORARY FILES
###############################################################################
log_info "Cleaning temporary files..."
rm -rf /tmp/* 2>/dev/null || true
rm -rf /var/tmp/* 2>/dev/null || true
rm -rf /root/.cache/* 2>/dev/null || true
rm -rf /home/*/.cache/* 2>/dev/null || true

###############################################################################
# 5. COMMAND HISTORY
###############################################################################
log_info "Cleaning command history..."
rm -f /root/.bash_history /root/.zsh_history
rm -f /home/*/.bash_history /home/*/.zsh_history 2>/dev/null || true
history -c
unset HISTFILE

###############################################################################
# 6. SSH CLEANUP
###############################################################################
log_info "Cleaning SSH data..."
# Remove SSH host keys - cloud-init will regenerate them
rm -f /etc/ssh/ssh_host_*

# Clean known_hosts but keep authorized_keys
rm -f /root/.ssh/known_hosts
find /home -name "known_hosts" -delete 2>/dev/null || true

###############################################################################
# 7. NETWORK CLEANUP
###############################################################################
log_info "Cleaning network data..."
rm -f /etc/udev/rules.d/70-persistent-net.rules
rm -f /var/lib/dhcp/*.leases
rm -f /var/lib/dhclient/* 2>/dev/null || true

###############################################################################
# 8. CLOUD-INIT CLEANUP
###############################################################################
log_info "Cleaning cloud-init..."
cloud-init clean --logs --seed 2>/dev/null || true

###############################################################################
# 9. MACHINE-ID
###############################################################################
log_info "Clearing machine-id..."
truncate -s 0 /etc/machine-id
rm -f /var/lib/dbus/machine-id
ln -sf /etc/machine-id /var/lib/dbus/machine-id 2>/dev/null || true

###############################################################################
# 10. MAIL
###############################################################################
rm -rf /var/mail/* /var/spool/mail/* 2>/dev/null || true

###############################################################################
# 11. AUDIT LOGS
###############################################################################
[ -d /var/log/audit ] && find /var/log/audit -type f -delete

###############################################################################
# 12. OPTIONAL: ZERO FREE SPACE
###############################################################################
log_warn "Zero free space for compression? (Ctrl+C to skip, 5 sec)"
sleep 5
log_info "Zeroing free space..."
dd if=/dev/zero of=/EMPTY bs=1M 2>/dev/null || true
rm -f /EMPTY
sync

###############################################################################
# DONE
###############################################################################
echo ""
log_info "======================================"
log_info "Template cleanup completed!"
log_info "======================================"
echo ""
log_info "Cleaned:"
echo "  ✓ Logs, caches, temp files"
echo "  ✓ SSH host keys (cloud-init will regenerate)"
echo "  ✓ machine-id (systemd will regenerate)"
echo "  ✓ Network leases"
echo "  ✓ Cloud-init data"
echo ""
log_info "Preserved:"
echo "  ✓ User accounts and SSH keys"
echo "  ✓ System configuration"
echo ""
log_warn "Next: shutdown -h now"
log_warn "Then convert to template"
echo ""

exit 0
