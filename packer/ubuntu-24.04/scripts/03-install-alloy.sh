#!/usr/bin/env bash
set -euxo pipefail
# Install Grafana Alloy for metrics/log collection

VER=${GRAFANA_ALLOY_VERSION:-1.11.3}
TMPDIR=$(mktemp -d)

echo "Installing Grafana Alloy version ${VER}..."

# Construct the download URL
DEB_URL="https://github.com/grafana/alloy/releases/download/v${VER}/grafana-alloy_${VER}-1.amd64.deb"
DEB_PATH="${TMPDIR}/grafana-alloy.deb"

# Verify URL before downloading
if ! curl -fsIL "${DEB_URL}" >/dev/null 2>&1; then
  echo "❌ ERROR: Could not find Alloy package at ${DEB_URL}"
  exit 1
fi

# Download and install
curl -fsSL -o "${DEB_PATH}" "${DEB_URL}"
dpkg -i "${DEB_PATH}" || apt-get -f install -y

mkdir -p /etc/alloy/conf.d

# Copy modular configuration files (if any)
if [ -d /tmp/alloy ]; then
  cp -r /tmp/alloy/* /etc/alloy/conf.d/ || true
fi

# Generate the main Alloy config
cat > /etc/alloy/config.alloy.yaml <<'EOF'
configs:
  - /etc/alloy/conf.d/base.yaml
  - /etc/alloy/conf.d/host-metrics.yaml
  - /etc/alloy/conf.d/host-logs.yaml
  - /etc/alloy/conf.d/docker-metrics.yaml
  - /etc/alloy/conf.d/docker-logs.yaml
  - /etc/alloy/conf.d/prometheus-loki.yaml
EOF

# Enable and start service
systemctl enable grafana-alloy || true
systemctl restart grafana-alloy || true

rm -rf "${TMPDIR}"
echo "✅ Grafana Alloy ${VER} installation completed successfully."
