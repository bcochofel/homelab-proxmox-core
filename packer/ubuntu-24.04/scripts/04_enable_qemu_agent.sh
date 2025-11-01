#!/bin/bash
set -e
echo "=== Enabling QEMU Guest Agent ==="
apt-get install -y qemu-guest-agent
systemctl enable qemu-guest-agent
systemctl start qemu-guest-agent
