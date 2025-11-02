#!/usr/bin/env bash
set -euo pipefail

# -------------------------------------------
# Configuration (override with env vars)
# -------------------------------------------
ETCD_VERSION="${ETCD_VERSION:-3.5.13}"
NODE_NAME="${NODE_NAME:-etcd-1}"
PRIVATE_IP="$(hostname -I | awk '{print $1}')"
ETCD_NODES="${ETCD_NODES:-10.0.0.1,10.0.0.2,10.0.0.3}"
ETCD_DATA_DIR="/var/lib/etcd"
ETCD_BIN_DIR="/usr/local/bin"
SYSTEMD_DIR="/etc/systemd/system"
CLUSTER_TOKEN="etcd-cluster-token"
USER="etcd"
GROUP="etcd"

# -------------------------------------------
# Helpers
# -------------------------------------------
_log() { echo "[$(date -Iseconds)] $*"; }

_log "Installing etcd v${ETCD_VERSION}..."

# -------------------------------------------
# Install etcd
# -------------------------------------------
apt-get update -y
apt-get install -y curl tar ca-certificates

TMPDIR=$(mktemp -d)
curl -L --fail "https://github.com/etcd-io/etcd/releases/download/v${ETCD_VERSION}/etcd-v${ETCD_VERSION}-linux-amd64.tar.gz" -o "${TMPDIR}/etcd.tar.gz"
tar -xzf "${TMPDIR}/etcd.tar.gz" -C "${TMPDIR}"
install -m 0755 "${TMPDIR}/etcd-v${ETCD_VERSION}-linux-amd64/etcd" "${ETCD_BIN_DIR}/etcd"
install -m 0755 "${TMPDIR}/etcd-v${ETCD_VERSION}-linux-amd64/etcdctl" "${ETCD_BIN_DIR}/etcdctl"
rm -rf "${TMPDIR}"

# -------------------------------------------
# Create etcd user and directories
# -------------------------------------------
id -u ${USER} &>/dev/null || useradd -r -s /sbin/nologin -M ${USER}
mkdir -p "${ETCD_DATA_DIR}"
chown -R ${USER}:${GROUP} "${ETCD_DATA_DIR}"

# -------------------------------------------
# Build cluster member list
# -------------------------------------------
INITIAL_CLUSTER=""
IFS=',' read -ra ADDR <<< "${ETCD_NODES}"
for i in "${!ADDR[@]}"; do
  name="etcd-$((i+1))"
  peer="http://${ADDR[$i]}:2380"
  if [ -z "$INITIAL_CLUSTER" ]; then
    INITIAL_CLUSTER="${name}=${peer}"
  else
    INITIAL_CLUSTER="${INITIAL_CLUSTER},${name}=${peer}"
  fi
done

_log "Etcd cluster peers: ${INITIAL_CLUSTER}"

# -------------------------------------------
# Create systemd service
# -------------------------------------------
cat > "${SYSTEMD_DIR}/etcd.service" <<EOF
[Unit]
Description=etcd key-value store
Documentation=https://etcd.io
After=network.target

[Service]
User=${USER}
Type=notify
ExecStart=${ETCD_BIN_DIR}/etcd \\
  --name ${NODE_NAME} \\
  --data-dir ${ETCD_DATA_DIR} \\
  --initial-advertise-peer-urls http://${PRIVATE_IP}:2380 \\
  --listen-peer-urls http://${PRIVATE_IP}:2380 \\
  --listen-client-urls http://${PRIVATE_IP}:2379,http://127.0.0.1:2379 \\
  --advertise-client-urls http://${PRIVATE_IP}:2379 \\
  --initial-cluster-token ${CLUSTER_TOKEN} \\
  --initial-cluster ${INITIAL_CLUSTER} \\
  --initial-cluster-state new
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

# -------------------------------------------
# Enable and start etcd
# -------------------------------------------
systemctl daemon-reload
systemctl enable etcd
systemctl restart etcd

sleep 5
systemctl --no-pager --full status etcd || true

_log "Etcd cluster node ${NODE_NAME} setup complete."
_log "Use 'etcdctl member list' to verify cluster health."
