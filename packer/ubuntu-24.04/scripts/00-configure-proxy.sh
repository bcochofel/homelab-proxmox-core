#!/usr/bin/env bash
set -euo pipefail
# Configure system-wide HTTP/HTTPS proxy settings if ENABLE_PROXY=true.
# Expected env vars: ENABLE_PROXY, HTTP_PROXY, HTTPS_PROXY, NO_PROXY

if [[ "${ENABLE_PROXY:-false}" == "true" ]]; then
  echo "==> Configuring system proxy..."

  cat > /etc/environment <<EOF
http_proxy=${HTTP_PROXY:-}
https_proxy=${HTTPS_PROXY:-}
no_proxy=${NO_PROXY:-}
HTTP_PROXY=${HTTP_PROXY:-}
HTTPS_PROXY=${HTTPS_PROXY:-}
NO_PROXY=${NO_PROXY:-}
EOF

  mkdir -p /etc/apt/apt.conf.d
  cat > /etc/apt/apt.conf.d/99proxy <<APT
Acquire::http::Proxy "${HTTP_PROXY:-}";
Acquire::https::Proxy "${HTTPS_PROXY:-}";
APT

  mkdir -p /etc/systemd/system/docker.service.d
  cat > /etc/systemd/system/docker.service.d/proxy.conf <<EOF
[Service]
Environment="HTTP_PROXY=${HTTP_PROXY:-}" "HTTPS_PROXY=${HTTPS_PROXY:-}" "NO_PROXY=${NO_PROXY:-}"
EOF

  systemctl daemon-reload || true
  echo "Proxy configuration applied."
else
  echo "==> Proxy disabled; skipping configuration."
fi
