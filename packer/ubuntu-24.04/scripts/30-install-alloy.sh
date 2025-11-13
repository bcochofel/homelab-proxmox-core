#!/usr/bin/env bash
set -euo pipefail
# Install Grafana Alloy for metrics and logs collection.

VER=${GRAFANA_ALLOY_VERSION:-1.11.3}
TMPDIR=$(mktemp -d)
DEB_URL=${GRAFANA_ALLOY_URL:-"https://github.com/grafana/alloy/releases/download/v${VER}/alloy-${VER}-1.amd64.deb"}
DEB_PATH="${TMPDIR}/grafana-alloy.deb"

echo "==> Installing Grafana Alloy ${VER} from ${DEB_URL}"
export DEBIAN_FRONTEND=noninteractive
export NEEDRESTART_MODE=a
export UCF_FORCE_CONFFNEW=YES

# Prevent auto-starting during dpkg install (packer-safe)
mkdir -p /run/systemd/system
cat > /run/systemd/system/policy-rc.d <<'EOF'
#!/bin/sh
exit 101
EOF
chmod +x /run/systemd/system/policy-rc.d

# Validate URL and download
if ! curl -fsIL "${DEB_URL}" >/dev/null 2>&1; then
  echo "ERROR: Alloy package not found at ${DEB_URL}" >&2
  exit 1
fi

curl -fsSL -o "${DEB_PATH}" "${DEB_URL}"
if [[ ! -s "${DEB_PATH}" ]]; then
  echo "ERROR: Empty file downloaded: ${DEB_PATH}" >&2
  exit 1
fi

dpkg -i "${DEB_PATH}" || apt-get -f install -y
rm -f /run/systemd/system/policy-rc.d || true

# Configuration
mkdir -p /etc/alloy/conf.d
if [[ -d /tmp/alloy ]]; then
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

systemctl daemon-reload || true
systemctl enable alloy || true
systemctl restart alloy || true

if command -v alloy >/dev/null 2>&1; then
  echo "==> Grafana Alloy installed successfully."
else
  echo "ERROR: Alloy binary not found after install" >&2
  exit 1
fi

rm -rf "${TMPDIR}"
