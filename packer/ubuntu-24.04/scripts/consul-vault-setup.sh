#!/usr/bin/env bash
set -euo pipefail

# ============================================================
#
# How this works
# The script installs and starts Consul everywhere (servers + clients).
# If the node’s role is server, it also:
# Installs and configures Vault
# Points Vault’s storage to the local Consul agent (127.0.0.1:8500)
# Enables Vault as a systemd service
# All Vault servers automatically join the same Consul backend — forming a Vault HA cluster.
#
# - Installs Consul from HashiCorp’s repo
# - Sets up Consul as a systemd service
# - Supports both “server” and “client” roles
# - Bootstraps a 3-node cluster automatically using environment variables
# - Installs Vault from HashiCorp’s repo
# - Configures Vault to use Consul as its storage backend
# - Automatically joins the Vault cluster using the same Consul cluster
# - Sets up Vault as a systemd service
# - Works for both server and client Consul roles (but Vault only starts on servers)
#
# | NODE_NAME | CONSUL_ROLE |    IP    |    CONSUL_CLUSTER_JOIN     |
# |-----------|-------------|----------|----------------------------|
# |  server1  |   server    | 10.0.0.1 |     10.0.0.2,10.0.0.3      |
# |  server2  |   server    | 10.0.0.2 |     10.0.0.1,10.0.0.3      |
# |  server3  |   server    | 10.0.0.3 |     10.0.0.1,10.0.0.2      |
# |  client1  |   client    | 10.0.1.1 | 10.0.0.1,10.0.0.2,10.0.0.3 |
# ============================================================
#
# Next Steps (Recommended)
# Once all servers are up:
# Initialize Vault (only once):
# $ vault operator init
# Unseal Vault on each server:
# $ vault operator unseal
# Verify cluster members:
# $ vault operator raft list-peers

# ============================================================
# CONFIGURATION VARIABLES
# ============================================================
CONSUL_VERSION="${CONSUL_VERSION:-1.20.0}"
VAULT_VERSION="${VAULT_VERSION:-1.18.2}"

CONSUL_USER="consul"
CONSUL_GROUP="consul"
CONSUL_DATA_DIR="/opt/consul"
CONSUL_CONFIG_DIR="/etc/consul.d"

VAULT_USER="vault"
VAULT_GROUP="vault"
VAULT_DATA_DIR="/opt/vault"
VAULT_CONFIG_DIR="/etc/vault.d"

NODE_NAME="${NODE_NAME:-$(hostname)}"
CONSUL_ROLE="${CONSUL_ROLE:-server}"             # server | client
CONSUL_CLUSTER_JOIN="${CONSUL_CLUSTER_JOIN:-}"
CONSUL_BOOTSTRAP_EXPECT="${CONSUL_BOOTSTRAP_EXPECT:-3}"

# ============================================================
# FUNCTIONS
# ============================================================

install_consul() {
  echo "[INFO] Installing Consul ${CONSUL_VERSION}..."
  apt-get update -y
  apt-get install -y unzip curl jq

  curl -sLo /tmp/consul.zip "https://releases.hashicorp.com/consul/${CONSUL_VERSION}/consul_${CONSUL_VERSION}_linux_amd64.zip"
  unzip -o /tmp/consul.zip -d /usr/local/bin/
  chmod 0755 /usr/local/bin/consul
  rm /tmp/consul.zip

  if ! id -u "$CONSUL_USER" >/dev/null 2>&1; then
    useradd --system --home "$CONSUL_DATA_DIR" --shell /bin/false "$CONSUL_USER"
  fi

  mkdir -p "$CONSUL_DATA_DIR" "$CONSUL_CONFIG_DIR"
  chown -R "$CONSUL_USER:$CONSUL_GROUP" "$CONSUL_DATA_DIR" "$CONSUL_CONFIG_DIR"

  echo "[INFO] Consul installed."
}

configure_consul() {
  echo "[INFO] Configuring Consul..."

  cat > "${CONSUL_CONFIG_DIR}/consul.hcl" <<EOF
datacenter = "dc1"
data_dir = "${CONSUL_DATA_DIR}"
node_name = "${NODE_NAME}"
bind_addr = "{{ GetInterfaceIP \"eth0\" }}"
retry_join = [${CONSUL_CLUSTER_JOIN//,/","}]
encrypt = "CHANGEME_WITH_YOUR_GOSSIP_KEY"
log_level = "INFO"
enable_script_checks = true
EOF

  if [[ "$CONSUL_ROLE" == "server" ]]; then
    cat >> "${CONSUL_CONFIG_DIR}/consul.hcl" <<EOF
server = true
bootstrap_expect = ${CONSUL_BOOTSTRAP_EXPECT}
EOF
  else
    cat >> "${CONSUL_CONFIG_DIR}/consul.hcl" <<EOF
server = false
EOF
  fi

  chown -R "$CONSUL_USER:$CONSUL_GROUP" "$CONSUL_CONFIG_DIR"
}

setup_consul_service() {
  echo "[INFO] Creating systemd service for Consul..."

  cat > /etc/systemd/system/consul.service <<EOF
[Unit]
Description=Consul Agent
After=network-online.target
Requires=network-online.target

[Service]
User=${CONSUL_USER}
Group=${CONSUL_GROUP}
ExecStart=/usr/local/bin/consul agent -config-dir=${CONSUL_CONFIG_DIR}
ExecReload=/bin/kill -HUP \$MAINPID
KillMode=process
Restart=on-failure
LimitNOFILE=65536

[Install]
WantedBy=multi-user.target
EOF

  systemctl daemon-reload
  systemctl enable consul
  systemctl restart consul
}

install_vault() {
  echo "[INFO] Installing Vault ${VAULT_VERSION}..."

  curl -sLo /tmp/vault.zip "https://releases.hashicorp.com/vault/${VAULT_VERSION}/vault_${VAULT_VERSION}_linux_amd64.zip"
  unzip -o /tmp/vault.zip -d /usr/local/bin/
  chmod 0755 /usr/local/bin/vault
  rm /tmp/vault.zip

  if ! id -u "$VAULT_USER" >/dev/null 2>&1; then
    useradd --system --home "$VAULT_DATA_DIR" --shell /bin/false "$VAULT_USER"
  fi

  mkdir -p "$VAULT_DATA_DIR" "$VAULT_CONFIG_DIR"
  chown -R "$VAULT_USER:$VAULT_GROUP" "$VAULT_DATA_DIR" "$VAULT_CONFIG_DIR"
}

configure_vault() {
  echo "[INFO] Configuring Vault (server mode only)..."

  cat > "${VAULT_CONFIG_DIR}/vault.hcl" <<EOF
ui = true
cluster_name = "vault-cluster"
disable_mlock = true

storage "consul" {
  address = "127.0.0.1:8500"
  path    = "vault/"
}

listener "tcp" {
  address     = "0.0.0.0:8200"
  tls_disable = 1
}

api_addr     = "http://$(hostname -I | awk '{print $1}'):8200"
cluster_addr = "http://$(hostname -I | awk '{print $1}'):8201"
EOF

  chown -R "$VAULT_USER:$VAULT_GROUP" "$VAULT_CONFIG_DIR"
}

setup_vault_service() {
  echo "[INFO] Creating Vault systemd service..."

  cat > /etc/systemd/system/vault.service <<EOF
[Unit]
Description=Vault Agent
After=network-online.target consul.service
Requires=consul.service

[Service]
User=${VAULT_USER}
Group=${VAULT_GROUP}
ExecStart=/usr/local/bin/vault server -config=${VAULT_CONFIG_DIR}
ExecReload=/bin/kill -HUP \$MAINPID
Restart=on-failure
LimitMEMLOCK=infinity
CapabilityBoundingSet=CAP_IPC_LOCK
AmbientCapabilities=CAP_IPC_LOCK
SecureBits=keep-caps

[Install]
WantedBy=multi-user.target
EOF

  systemctl daemon-reload
  systemctl enable vault
  systemctl restart vault
}

# ============================================================
# MAIN EXECUTION FLOW
# ============================================================

install_consul
configure_consul
setup_consul_service

if [[ "$CONSUL_ROLE" == "server" ]]; then
  install_vault
  configure_vault
  setup_vault_service
  echo "[INFO] Vault cluster setup complete on server node."
else
  echo "[INFO] Skipping Vault setup (client node)."
fi

echo "[INFO] Consul + Vault installation complete on ${NODE_NAME}."
