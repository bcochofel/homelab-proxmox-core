#!/usr/bin/env bash
set -euxo pipefail
# Install Grafana Alloy for metrics/log collection (non-interactive, Packer-safe)

VER=${GRAFANA_ALLOY_VERSION:-1.11.3}
TMPDIR=$(mktemp -d)
DEB_URL=${GRAFANA_ALLOY_URL:-"https://github.com/grafana/alloy/releases/download/v${VER}/alloy-${VER}-1.amd64.deb"}
DEB_PATH="${TMPDIR}/grafana-alloy.deb"

echo "Installing Grafana Alloy version ${VER}..."
echo "Downloading from ${DEB_URL}"

# --- Ensure apt and dpkg run non-interactively ---
export DEBIAN_FRONTEND=noninteractive
export NEEDRESTART_MODE=a
export UCF_FORCE_CONFFNEW=YES

# --- Disable service auto-start to avoid systemd hang during dpkg ---
echo "Temporarily disabling automatic service starts..."
mkdir -p /run/systemd/system
cat > /run/systemd/system/policy-rc.d <<'EOF'
#!/bin/sh
exit 101
EOF
chmod +x /run/systemd/system/policy-rc.d

# --- Verify URL before downloading ---
if ! curl -fsIL "${DEB_URL}" >/dev/null 2>&1; then
  echo "❌ ERROR: Could not find Alloy package at ${DEB_URL}"
  exit 1
fi

# --- Download and install .deb ---
curl -fsSL -o "${DEB_PATH}" "${DEB_URL}"
if [ ! -s "${DEB_PATH}" ]; then
  echo "❌ ERROR: Failed to download Alloy package (${DEB_PATH} missing or empty)."
  exit 1
fi

echo "Installing package..."
dpkg -i "${DEB_PATH}" || apt-get -f install -y

# --- Re-enable service starts ---
rm -f /run/systemd/system/policy-rc.d

# --- Configuration setup ---
mkdir -p /etc/alloy/conf.d
if [ -d /tmp/alloy ]; then
  cp -r /tmp/alloy/* /etc/alloy/conf.d/ || true
fi

cat > /etc/alloy/config.alloy.yaml <<'EOF'
configs:
  - /etc/alloy/conf.d/base.yaml
  - /etc/alloy/conf.d/host-metrics.yaml
  - /etc/alloy/conf.d/host-logs.yaml
  - /etc/alloy/conf.d/docker-metrics.yaml
  - /etc/alloy/conf.d/docker-logs.yaml
  - /etc/alloy/conf.d/prometheus-loki.yaml
EOF

# --- Start service safely ---
if systemctl list-unit-files | grep -q grafana-alloy.service; then
  echo "Enabling and starting Grafana Alloy service..."
  systemctl daemon-reload
  systemctl enable grafana-alloy || true
  systemctl restart grafana-alloy || true
else
  echo "⚠️ grafana-alloy.service not found; continuing."
fi

rm -rf "${TMPDIR}"
echo "✅ Grafana Alloy ${VER} installation completed successfully."
