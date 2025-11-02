#!/usr/bin/env bash
set -euo pipefail

# -------------------------------------------
# Configurable variables (set in Packer)
# -------------------------------------------
USE_PROXY="${USE_PROXY:-false}"
HTTP_PROXY="${HTTP_PROXY:-}"
HTTPS_PROXY="${HTTPS_PROXY:-}"
NO_PROXY="${NO_PROXY:-localhost,127.0.0.1}"

_log() { echo "[$(date -Iseconds)] $*"; }

if [[ "${USE_PROXY}" != "true" ]]; then
  _log "Proxy not enabled (USE_PROXY=${USE_PROXY}). Skipping setup."
  exit 0
fi

_log "Applying system-wide HTTP/HTTPS proxy configuration..."

# 1. System environment
cat > /etc/environment <<EOF
HTTP_PROXY="${HTTP_PROXY}"
HTTPS_PROXY="${HTTPS_PROXY}"
NO_PROXY="${NO_PROXY}"
http_proxy="${HTTP_PROXY}"
https_proxy="${HTTPS_PROXY}"
no_proxy="${NO_PROXY}"
EOF

# 2. APT proxy
mkdir -p /etc/apt/apt.conf.d
cat > /etc/apt/apt.conf.d/95proxies <<EOF
Acquire {
  HTTP::proxy "${HTTP_PROXY}";
  HTTPS::proxy "${HTTPS_PROXY}";
  No-Proxy "${NO_PROXY}";
}
EOF

# 3. Docker daemon and client proxy (optional)
mkdir -p /etc/systemd/system/docker.service.d
cat > /etc/systemd/system/docker.service.d/proxy.conf <<EOF
[Service]
Environment="HTTP_PROXY=${HTTP_PROXY}"
Environment="HTTPS_PROXY=${HTTPS_PROXY}"
Environment="NO_PROXY=${NO_PROXY}"
EOF

mkdir -p /etc/docker
cat > /etc/docker/config.json <<EOF
{
  "proxies": {
    "default": {
      "httpProxy": "${HTTP_PROXY}",
      "httpsProxy": "${HTTPS_PROXY}",
      "noProxy": "${NO_PROXY}"
    }
  }
}
EOF

systemctl daemon-reexec || true
systemctl daemon-reload || true

_log "Proxy configuration applied successfully."
