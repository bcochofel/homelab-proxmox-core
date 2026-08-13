#!/bin/bash

###############################################################################
# Ubuntu 26.04 Template Fix: no networking in the initrd
# Purpose: Stop dracut from bringing up the NIC via DHCP before cloud-init
#          gets a chance to rename+configure it (see ADR-6 in README.md)
# Usage: Run this script as root
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

if ! command -v dracut &>/dev/null; then
  log_warn "dracut not found on this image; skipping (nothing to fix)."
  exit 0
fi

log_info "Omitting network dracut modules (this root is local LVM only — no NFS root, no network unlock)..."
cat >/etc/dracut.conf.d/99-omit-network.conf <<'EOF'
# Managed by Packer (scripts/15-fix-initrd-network.sh).
#
# This template's root filesystem is local LVM — nothing in the initrd
# needs networking. Dracut's default hostonly mode auto-includes network
# modules based on what's active on the BUILD machine (which has internet
# for package installs), not what the target's actual boot path needs.
# That over-inclusion caused a real race: the initrd's systemd-networkd
# DHCPs the NIC before cloud-init's netplan config gets a chance to rename
# + statically configure it, and the rename then fails because the
# interface is already up ("[busy] Error renaming ... from ens18 to eth0").
# See ADR-6 in packer/ubuntu-26.04/README.md for the full incident.
omit_dracutmodules+=" 05dyn-netconf 10systemd-network-management 11systemd-networkd 35network-manager 40network 45net-lib 70kernel-network-modules 70livenet 70qemu-net "

# 45systemd-import (machinectl pull-tar/pull-raw support — irrelevant here)
# unconditionally depends() on "network", and dracut force-includes hard
# dependencies regardless of the omit list above. Its check() passes on any
# host with the stock systemd-importd binary present, which is why this
# needed omitting explicitly rather than being pulled out by the omit list
# above alone.
omit_dracutmodules+=" 45systemd-import "
EOF

# Belt and suspenders: even with every network-pulling module identified
# and omitted above, mask the actual systemd-networkd units directly
# inside the initrd via a tiny custom dracut module that installs last
# (99- prefix). A masked unit (symlinked to /dev/null under
# /etc/systemd/system/) never starts regardless of any .wants/ enablement
# symlink some other module creates — this is what actually guarantees
# nothing DHCPs the NIC before cloud-init runs, independent of chasing
# dracut's full dependency graph for every possible way "network" gets
# pulled back in.
log_info "Masking systemd-networkd units inside the initrd (defense in depth)..."
mkdir -p /usr/lib/dracut/modules.d/99disable-networkd
cat >/usr/lib/dracut/modules.d/99disable-networkd/module-setup.sh <<'EOF'
#!/bin/bash
# Managed by Packer (scripts/15-fix-initrd-network.sh) — see ADR-6 in
# packer/ubuntu-26.04/README.md.
check() { return 0; }
depends() { return 0; }
install() {
  mkdir -p "${initdir}/etc/systemd/system"
  for unit in systemd-networkd.service systemd-networkd.socket systemd-networkd-wait-online.service systemd-network-generator.service; do
    ln -sf /dev/null "${initdir}/etc/systemd/system/${unit}"
  done
}
EOF
chmod +x /usr/lib/dracut/modules.d/99disable-networkd/module-setup.sh

log_info "Regenerating initramfs for all installed kernels..."
# NOT `dracut --force --regenerate-all`: per dracut(8), --regenerate-all
# rebuilds each existing image "using the same command line options and
# dracut modules that were used when they were created" — i.e. it replays
# the ORIGINAL build flags recorded for each image rather than re-reading
# current /etc/dracut.conf.d/*.conf. Since these images were built before
# the config above existed, --regenerate-all silently kept including the
# network modules. A plain `dracut --force <image> <kver>` per installed
# kernel forces a fresh config read instead.
for kver in $(ls /lib/modules 2>/dev/null); do
  log_info "  -> /boot/initrd.img-${kver}"
  dracut --force "/boot/initrd.img-${kver}" "${kver}"
done

log_info "Verifying systemd-networkd is masked in the regenerated initrd..."
FAILED=0
for img in /boot/initrd.img-*; do
  [ -e "$img" ] || continue
  UNPACK_DIR="$(mktemp -d)"
  unmkinitramfs "$img" "$UNPACK_DIR" >/dev/null 2>&1
  LINK_PATH="$(find "$UNPACK_DIR" -path '*/etc/systemd/system/systemd-networkd.service' | head -n1)"
  if [ -n "$LINK_PATH" ] && [ -L "$LINK_PATH" ] && [ "$(readlink "$LINK_PATH")" = "/dev/null" ]; then
    log_info "  $img: systemd-networkd.service is masked."
  else
    log_error "  $img: systemd-networkd.service is NOT masked (found: $(readlink "$LINK_PATH" 2>/dev/null || echo 'missing/not a symlink'))."
    FAILED=1
  fi
  rm -rf "$UNPACK_DIR"
done

if [ "$FAILED" -ne 0 ]; then
  log_error "systemd-networkd masking did not take effect — aborting build."
  exit 1
fi

log_info "Confirmed: systemd-networkd is masked in every installed kernel's initrd."
