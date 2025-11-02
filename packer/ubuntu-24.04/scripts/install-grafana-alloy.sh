#!/usr/bin/env bash
set -euo pipefail

# ----------------------------------------------------------
# Configurable variables (set in Packer or environment)
# ----------------------------------------------------------
ALLOY_VERSION="${ALLOY_VERSION:-latest}"
ALLOY_CONFIG_PATH="/etc/alloy/config.alloy"

PROMETHEUS_ENDPOINTS="${PROMETHEUS_ENDPOINTS:-}" # comma-separated list
LOKI_ENDPOINTS="${LOKI_ENDPOINTS:-}"             # comma-separated list
CILIUM_METRICS_URL="${CILIUM_METRICS_URL:-http://localhost:9090/metrics}"
HUBBLE_METRICS_URL="${HUBBLE_METRICS_URL:-http://localhost:9091/metrics}"

_log() { echo "[$(date -Iseconds)] $*"; }

# ----------------------------------------------------------
# 1. Install dependencies
# ----------------------------------------------------------
_log "Installing dependencies..."
apt-get update -y
apt-get install -y curl unzip systemd jq

# ----------------------------------------------------------
# 2. Download and install Grafana Alloy
# ----------------------------------------------------------
_log "Installing Grafana Alloy..."

TMP_DIR=$(mktemp -d)
cd "$TMP_DIR"

if [[ "$ALLOY_VERSION" == "latest" ]]; then
  LATEST_URL=$(curl -s https://api.github.com/repos/grafana/alloy/releases/latest | jq -r '.assets[] | select(.name | test("linux-amd64.zip$")) | .browser_download_url')
else
  LATEST_URL="https://github.com/grafana/alloy/releases/download/v${ALLOY_VERSION}/alloy-linux-amd64.zip"
fi

curl -fsSL -o alloy.zip "$LATEST_URL"
unzip alloy.zip
install -m 0755 alloy /usr/local/bin/alloy

mkdir -p /etc/alloy /var/lib/alloy
useradd --system --no-create-home --shell /usr/sbin/nologin alloy || true
chown -R alloy:alloy /etc/alloy /var/lib/alloy

# ----------------------------------------------------------
# 3. Generate Alloy configuration
# ----------------------------------------------------------
_log "Creating Alloy configuration at $ALLOY_CONFIG_PATH..."

cat > "$ALLOY_CONFIG_PATH" <<'EOF'
# ---------------------------------------------
# Grafana Alloy configuration
# ---------------------------------------------
logging {
  level = "info"
  format = "logfmt"
}

# --- Host metrics ---
prometheus.scrape "host_metrics" {
  targets = [
    { __address__ = "localhost:9100" },
  ]
  forward_to = [prometheus.remote_write.default.receiver]
}

# --- Docker container metrics ---
prometheus.scrape "container_metrics" {
  targets = [
    { __address__ = "localhost:9323" }, # docker metrics endpoint
  ]
  forward_to = [prometheus.remote_write.default.receiver]
}

# --- Cilium metrics ---
prometheus.scrape "cilium_metrics" {
  targets = [
    { __address__ = "localhost:9090" },
  ]
  forward_to = [prometheus.remote_write.default.receiver]
}

# --- Hubble metrics ---
prometheus.scrape "hubble_metrics" {
  targets = [
    { __address__ = "localhost:9091" },
  ]
  forward_to = [prometheus.remote_write.default.receiver]
}

# --- Loki log collection ---
loki.source.journal "system_logs" {
  forward_to = [loki.write.default.receiver]
}

loki.source.file "docker_logs" {
  targets = [
    { __path__ = "/var/lib/docker/containers/*/*.log" },
  ]
  forward_to = [loki.write.default.receiver]
}
EOF

# ----------------------------------------------------------
# 4. Add optional Prometheus configuration
# ----------------------------------------------------------
if [[ -n "${PROMETHEUS_ENDPOINTS}" ]]; then
  _log "Adding Prometheus remote_write configuration..."
  {
    echo ""
    echo "# --- Remote write to Prometheus ---"
    IFS=',' read -ra ENDPOINTS <<<"$PROMETHEUS_ENDPOINTS"
    echo 'prometheus.remote_write "default" {'
    echo '  endpoints = ['
    for ep in "${ENDPOINTS[@]}"; do
      echo "    { url = \"${ep}\" },"
    done
    echo '  ]'
    echo '}'
  } >> "$ALLOY_CONFIG_PATH"
else
  _log "No Prometheus endpoints set; skipping remote_write."
fi

# ----------------------------------------------------------
# 5. Add optional Loki configuration
# ----------------------------------------------------------
if [[ -n "${LOKI_ENDPOINTS}" ]]; then
  _log "Adding Loki remote_write configuration..."
  {
    echo ""
    echo "# --- Remote write to Loki ---"
    IFS=',' read -ra LOKI_EPS <<<"$LOKI_ENDPOINTS"
    echo 'loki.write "default" {'
    echo '  endpoints = ['
    for ep in "${LOKI_EPS[@]}"; do
      echo "    { url = \"${ep}\" },"
    done
    echo '  ]'
    echo '}'
  } >> "$ALLOY_CONFIG_PATH"
else
  _log "No Loki endpoints set; skipping remote_write."
fi

chown alloy:alloy "$ALLOY_CONFIG_PATH"

# ----------------------------------------------------------
# 6. Create systemd service
# ----------------------------------------------------------
_log "Creating systemd unit for Alloy..."

cat > /etc/systemd/system/alloy.service <<EOF
[Unit]
Description=Grafana Alloy
After=network-online.target
Wants=network-online.target

[Service]
User=alloy
Group=alloy
ExecStart=/usr/local/bin/alloy run --config.file=${ALLOY_CONFIG_PATH}
Restart=on-failure
RestartSec=10
LimitNOFILE=65536

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable alloy
systemctl restart alloy

# ----------------------------------------------------------
# 7. Verify
# ----------------------------------------------------------
sleep 3
systemctl --no-pager --full status alloy || true

_log "Grafana Alloy installed and configured successfully."
