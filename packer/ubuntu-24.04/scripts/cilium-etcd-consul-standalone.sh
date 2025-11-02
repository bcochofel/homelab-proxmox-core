#!/usr/bin/env bash
set -euo pipefail
# cilium-etcd-consul-standalone.sh
# - Installs optional etcd cluster (if ENABLE_ETCD=true)
# - Installs Cilium standalone (kvstore=etcd)
# - Installs clustermesh-apiserver (kvstoremesh) for cross-cluster sync
# - Configures Cilium to use Consul as a service registry (service discovery)
# - Applies BPF/XDP tuning and ulimit changes
# - Installs Hubble relay only (UI runs elsewhere)
#
# Usage: set env variables for Packer provisioner or run manually.
#
# Environment variables (defaults shown):
# ENABLE_ETCD=true
# ETCD_CLUSTER_NODES="10.0.0.1,10.0.0.2,10.0.0.3"
# ENABLE_XDP=true
# BPF_MAP_MAX_ENTRIES=262144
# ENABLE_HUBBLE_RELAY=true
# CLUSTER_NAME="site-a"
# CLUSTER_ID=1
# KVSTORE_ENDPOINTS (optional; defaults to http://127.0.0.1:2379 if etcd local)
# CONSUL_ADDR="127.0.0.1:8500"   # address where this node can reach Consul agent
# CILIUM_VERSION="1.14.0"
# ETCD_VER="v3.5.13"

# -----------------------------
# Configurable variables
# -----------------------------
CILIUM_VERSION="${CILIUM_VERSION:-1.14.0}"
CLUSTERMESH_APISERVER_VERSION="${CLUSTERMESH_APISERVER_VERSION:-${CILIUM_VERSION}}"
HUBBLE_VERSION="${HUBBLE_VERSION:-0.13.0}"

ENABLE_ETCD="${ENABLE_ETCD:-true}"
ETCD_CLUSTER_NODES="${ETCD_CLUSTER_NODES:-}"  # comma-separated IPs (required when ENABLE_ETCD=true)
ETCD_VER="${ETCD_VER:-v3.5.13}"
ETCD_DATA_DIR="${ETCD_DATA_DIR:-/var/lib/etcd}"

ENABLE_XDP="${ENABLE_XDP:-true}"
BPF_MAP_MAX_ENTRIES="${BPF_MAP_MAX_ENTRIES:-262144}"
ULIMIT_NOFILE="${ULIMIT_NOFILE:-1048576}"

ENABLE_HUBBLE_RELAY="${ENABLE_HUBBLE_RELAY:-true}"

CLUSTER_NAME="${CLUSTER_NAME:-cluster-$(hostname -s)}"
CLUSTER_ID="${CLUSTER_ID:-1}"

# Consul service discovery (only service registry)
CONSUL_ADDR="${CONSUL_ADDR:-127.0.0.1:8500}"

# KV store endpoints (etcd). If empty and ENABLE_ETCD=true we set to local after etcd started.
KVSTORE_ENDPOINTS="${KVSTORE_ENDPOINTS:-}"

CILIUM_BIN_DIR="${CILIUM_BIN_DIR:-/usr/local/bin}"
CILIUM_CONFIG_DIR="${CILIUM_CONFIG_DIR:-/etc/cilium}"
CILIUM_SYSTEMD_DIR="${CILIUM_SYSTEMD_DIR:-/etc/systemd/system}"

_log(){ echo "[$(date -Iseconds)] $*"; }

# -----------------------------
# Prereqs
# -----------------------------
_log "Installing OS prerequisites..."
export DEBIAN_FRONTEND=noninteractive
apt-get update -y
apt-get install -y curl jq tar apt-transport-https ca-certificates gnupg lsb-release \
  conntrack iproute2 iptables bpfcc-tools libbpfcc-tools

# -----------------------------
# Etcd installation (optional)
# -----------------------------
if [[ "${ENABLE_ETCD}" == "true" ]]; then
  if [[ -z "${ETCD_CLUSTER_NODES}" ]]; then
    echo "ERROR: ENABLE_ETCD=true but ETCD_CLUSTER_NODES is empty. Set ETCD_CLUSTER_NODES and retry."
    exit 1
  fi

  _log "Installing etcd ${ETCD_VER}..."
  if ! command -v etcd >/dev/null 2>&1; then
    TMP=$(mktemp -d)
    curl -sSL "https://github.com/etcd-io/etcd/releases/download/${ETCD_VER}/etcd-${ETCD_VER}-linux-amd64.tar.gz" -o "${TMP}/etcd.tar.gz"
    tar -xzf "${TMP}/etcd.tar.gz" -C "${TMP}"
    install -m 0755 "${TMP}/etcd-${ETCD_VER}-linux-amd64/etcd" "${CILIUM_BIN_DIR}/etcd"
    install -m 0755 "${TMP}/etcd-${ETCD_VER}-linux-amd64/etcdctl" "${CILIUM_BIN_DIR}/etcdctl"
    rm -rf "${TMP}"
  else
    _log "etcd already installed"
  fi

  # prepare data dir and user
  mkdir -p "${ETCD_DATA_DIR}"
  id -u etcd &>/dev/null || useradd -r -s /sbin/nologin etcd
  chown -R etcd:etcd "${ETCD_DATA_DIR}"

  # build initial cluster string
  IFS=',' read -r -a _nodes <<< "${ETCD_CLUSTER_NODES}"
  initial_cluster_entries=()
  for i in "${!_nodes[@]}"; do
    ip="${_nodes[$i]}"
    name="etcd-${i}"
    initial_cluster_entries+=("${name}=http://${ip}:2380")
  done
  initial_cluster=$(IFS=,; echo "${initial_cluster_entries[*]}")

  HOST_IP="$(hostname -I | awk '{print $1}')"
  # find index of this host in ETCD_CLUSTER_NODES to determine name; if not present, use hostname-based name
  this_name="etcd-local"
  advertise_client_urls="http://${HOST_IP}:2379"
  advertise_peer_urls="http://${HOST_IP}:2380"
  # attempt to map host ip to cluster list
  for i in "${!_nodes[@]}"; do
    if [[ "${_nodes[$i]}" == "${HOST_IP}" ]]; then
      this_name="etcd-${i}"
      break
    fi
  done

  _log "Configuring etcd systemd service (name=${this_name})..."
  cat > /etc/systemd/system/etcd.service <<EOF
[Unit]
Description=etcd key-value store
After=network.target

[Service]
User=etcd
Type=notify
ExecStart=${CILIUM_BIN_DIR}/etcd \\
  --name ${this_name} \\
  --data-dir ${ETCD_DATA_DIR} \\
  --initial-advertise-peer-urls ${advertise_peer_urls} \\
  --listen-peer-urls ${advertise_peer_urls} \\
  --listen-client-urls http://127.0.0.1:2379,${advertise_client_urls} \\
  --advertise-client-urls ${advertise_client_urls} \\
  --initial-cluster ${initial_cluster} \\
  --initial-cluster-state new
Restart=always
RestartSec=5
LimitNOFILE=65536

[Install]
WantedBy=multi-user.target
EOF

  systemctl daemon-reload
  systemctl enable etcd
  systemctl restart etcd
  _log "Waiting briefly for etcd to start..."
  sleep 6
  systemctl status etcd --no-pager || true

  # set KVSTORE_ENDPOINTS to local if not provided
  if [[ -z "${KVSTORE_ENDPOINTS}" ]]; then
    KVSTORE_ENDPOINTS="http://127.0.0.1:2379"
  fi

  _log "Etcd install done. Using KVSTORE_ENDPOINTS=${KVSTORE_ENDPOINTS}"
fi

# -----------------------------
# BPF / XDP / kernel tuning
# -----------------------------
_log "Applying BPF/XDP and kernel tunings..."

# sysctl tuning recommendations (validate in your environment)
cat > /etc/sysctl.d/99-cilium-tuning.conf <<EOF
net.core.rmem_max=2500000
net.core.wmem_max=2500000
net.ipv4.ip_forward=1
net.netfilter.nf_conntrack_max=524288
net.core.netdev_max_backlog=250000
net.ipv4.neigh.default.gc_thresh1=1024
net.ipv4.neigh.default.gc_thresh2=2048
net.ipv4.neigh.default.gc_thresh3=4096
EOF

sysctl --system || true

# increase ulimits
if ! grep -q "cilium" /etc/security/limits.conf 2>/dev/null; then
  cat >> /etc/security/limits.conf <<EOF
*               soft    nofile          ${ULIMIT_NOFILE}
*               hard    nofile          ${ULIMIT_NOFILE}
EOF
fi

# -----------------------------
# Install Cilium standalone binaries
# -----------------------------
_log "Installing Cilium ${CILIUM_VERSION} (standalone agent + clustermesh-apiserver)..."
if ! command -v cilium-agent >/dev/null 2>&1; then
  TMP=$(mktemp -d)
  curl -sL "https://github.com/cilium/cilium/releases/download/v${CILIUM_VERSION}/cilium-linux-amd64.tar.gz" | tar -xz -C "${TMP}"
  install -m 0755 "${TMP}/cilium" "${CILIUM_BIN_DIR}/cilium" || true
  install -m 0755 "${TMP}/cilium-agent" "${CILIUM_BIN_DIR}/cilium-agent" || true
  install -m 0755 "${TMP}/clustermesh-apiserver" "${CILIUM_BIN_DIR}/clustermesh-apiserver" || true
  rm -rf "${TMP}"
else
  _log "Cilium already installed"
fi

mkdir -p "${CILIUM_CONFIG_DIR}"
chown -R root:root "${CILIUM_CONFIG_DIR}"

# Compose cilium config for standalone mode: etcd as kvstore + consul as service registry
_log "Writing Cilium configuration (kvstore=etcd, service-registry=consul)..."

cat > "${CILIUM_CONFIG_DIR}/cilium.conf" <<EOF
# cilium standalone configuration (generated)
bpf-root=/sys/fs/bpf
datapath-mode=veth
disable-k8s-api-discovery=true
enable-ipv4=true
enable-ipv6=false
enable-hubble=true
kvstore=etcd
# etcd endpoints: either provided externally or local
kvstore-opt=etcd.address=${KVSTORE_ENDPOINTS}
# Cluster mesh / map tuning
bpf-map-max-num-entries=${BPF_MAP_MAX_ENTRIES}
# XDP
enable-xdp=${ENABLE_XDP}
# Service discovery via Consul
service-registry=consul
consul.address=${CONSUL_ADDR}
# DNS enrichment: helpful to resolve names to identities
enable-dnsproxy=true
enable-dns-name-based-identity=true
# by default, we are not enabling policy to avoid blocking traffic until tested
enable-policy=false
EOF

_log "Cilium config written to ${CILIUM_CONFIG_DIR}/cilium.conf"

# -----------------------------
# Systemd unit for cilium-agent
# -----------------------------
_log "Creating systemd unit for cilium-agent..."
cat > "${CILIUM_SYSTEMD_DIR}/cilium.service" <<'EOF'
[Unit]
Description=Cilium Agent (Standalone)
After=network-online.target
Wants=network-online.target

[Service]
ExecStart=/usr/local/bin/cilium-agent --config-dir=/etc/cilium
Restart=always
RestartSec=10
LimitNOFILE=65536
Environment=PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable cilium
systemctl restart cilium
sleep 3
systemctl status cilium --no-pager || true

# -----------------------------
# clustermesh-apiserver (kvstoremesh)
# -----------------------------
_log "Configuring clustermesh-apiserver (kvstoremesh) to point at ${KVSTORE_ENDPOINTS}..."
cat > /etc/systemd/system/clustermesh-apiserver.service <<EOF
[Unit]
Description=Cilium clustermesh-apiserver (kvstoremesh)
After=network-online.target etcd.service
Requires=etcd.service

[Service]
ExecStart=/usr/local/bin/clustermesh-apiserver \\
  --cluster-name ${CLUSTER_NAME} \\
  --cluster-id ${CLUSTER_ID} \\
  --api-serve-addr 0.0.0.0:9889 \\
  --kvstore-endpoints ${KVSTORE_ENDPOINTS}
Restart=on-failure
LimitNOFILE=65536

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable clustermesh-apiserver
systemctl restart clustermesh-apiserver
sleep 2
systemctl status clustermesh-apiserver --no-pager || true

# -----------------------------
# Hubble Relay (only)
# -----------------------------
if [[ "${ENABLE_HUBBLE_RELAY}" == "true" ]]; then
  _log "Installing Hubble relay (if needed) and configuring service..."
  if ! command -v hubble >/dev/null 2>&1; then
    TMP=$(mktemp -d)
    curl -sL "https://github.com/cilium/hubble/releases/download/v${HUBBLE_VERSION}/hubble-linux-amd64.tar.gz" | tar -xz -C "${TMP}"
    install -m 0755 "${TMP}/hubble" "${CILIUM_BIN_DIR}/hubble" || true
    install -m 0755 "${TMP}/hubble-relay" "${CILIUM_BIN_DIR}/hubble-relay" || true
    rm -rf "${TMP}"
  fi

  cat > /etc/systemd/system/hubble-relay.service <<'EOF'
[Unit]
Description=Hubble Relay
After=network-online.target cilium.service
Requires=cilium.service

[Service]
ExecStart=/usr/local/bin/hubble relay --listen :4245
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

  systemctl daemon-reload
  systemctl enable hubble-relay
  systemctl restart hubble-relay
  sleep 2
  systemctl status hubble-relay --no-pager || true
fi

_log "Setup complete."

# -----------------------------
# Verification hints
# -----------------------------
cat <<EOF

VERIFICATION (examples):
- Check etcd cluster (if enabled):
  ETCDCTL_API=3 etcdctl --endpoints="${KVSTORE_ENDPOINTS}" member list

- Check cilium status and that it sees Consul as service registry:
  sudo cilium status
  sudo journalctl -u cilium -n 200

- Check clustermesh apiserver:
  sudo systemctl status clustermesh-apiserver

- Check hubble relay:
  sudo systemctl status hubble-relay
  /usr/local/bin/hubble status

- To verify service discovery enrichment (requires services registered in Consul):
  hubble observe --last 10

EOF

# -----------------------------
# End of script
# -----------------------------
