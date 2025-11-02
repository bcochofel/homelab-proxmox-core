#!/usr/bin/env bash
set -euo pipefail

# -------------------------------------------
# Configuration (override with env vars)
# -------------------------------------------
CILIUM_VERSION="${CILIUM_VERSION:-1.14.0}"
HUBBLE_ENABLED="${HUBBLE_ENABLED:-false}" # you’ll run Hubble UI elsewhere
ETCD_ENDPOINTS="${ETCD_ENDPOINTS:-http://10.0.0.1:2379,http://10.0.0.2:2379,http://10.0.0.3:2379}"

# Paths
CILIUM_DIR="/etc/cilium"
BIN_DIR="/usr/local/bin"
SYSTEMD_DIR="/etc/systemd/system"

_log() { echo "[$(date -Iseconds)] $*"; }

# -------------------------------------------
# Install dependencies
# -------------------------------------------
apt-get update -y
DEBIAN_FRONTEND=noninteractive apt-get install -y \
  bpfcc-tools iproute2 iptables curl jq conntrack ca-certificates

# -------------------------------------------
# Install Cilium binary
# -------------------------------------------
if ! command -v cilium-agent >/dev/null 2>&1; then
  _log "Installing Cilium v${CILIUM_VERSION}..."
  curl -L "https://github.com/cilium/cilium/releases/download/v${CILIUM_VERSION}/cilium-linux-amd64.tar.gz" \
    | tar -xz -C /tmp
  install -m 0755 /tmp/cilium-linux-amd64/cilium-agent ${BIN_DIR}/cilium-agent
  install -m 0755 /tmp/cilium-linux-amd64/cilium ${BIN_DIR}/cilium
  rm -rf /tmp/cilium-linux-amd64
fi

# -------------------------------------------
# Configure Cilium
# -------------------------------------------
_log "Configuring Cilium with etcd backend..."

mkdir -p "${CILIUM_DIR}"
cat > "${CILIUM_DIR}/cilium.conf" <<EOF
bpf-root=/sys/fs/bpf
bpf-map-dynamic-size-ratio=0.0025
bpf-lb-map-max=65536
bpf-policy-map-max=16384
datapath-mode=veth
enable-ipv4=true
enable-ipv6=false
enable-bpf-clock-probe=true
enable-ipv4-masquerade=true
enable-hubble=${HUBBLE_ENABLED}
disable-k8s-api-discovery=true
kvstore=etcd
kvstore-opt=etcd.config=/etc/cilium/etcd-config.yaml
EOF

# -------------------------------------------
# etcd client config
# -------------------------------------------
cat > "${CILIUM_DIR}/etcd-config.yaml" <<EOF
endpoints:
  - ${ETCD_ENDPOINTS}
EOF

# (Optionally you can add TLS config here)

_log "Cilium config created at ${CILIUM_DIR}/"

# -------------------------------------------
# Systemd service
# -------------------------------------------
cat > "${SYSTEMD_DIR}/cilium.service" <<'EOF'
[Unit]
Description=Cilium Agent (Standalone - etcd backend)
After=network-online.target
Wants=network-online.target

[Service]
ExecStart=/usr/local/bin/cilium-agent --config-dir=/etc/cilium
Restart=always
RestartSec=10
LimitNOFILE=65535
Environment=PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable cilium
systemctl restart cilium

sleep 5
systemctl --no-pager --full status cilium || true

_log "Cilium running with etcd backend."
_log "You can verify with: cilium status"
