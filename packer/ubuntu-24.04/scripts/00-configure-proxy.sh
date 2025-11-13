#!/bin/bash

###############################################################################
# Ubuntu 24.04 Template Configure HTTP Proxy
# Purpose: Configure HTTP Proxy
# Usage: Run this script as root
# Expected env vars:
# ENABLE_PROXY: If true will configure proxy
# HTTP_PROXY: will be used to create http_proxy, and HTTP_PROXY env vars
# HTTP_PROXYS: will be used to create https_proxy, and HTTPs_PROXY env vars
# NO_PROXY: will be used to create no_proxy, and NO_PROXY env vars
###############################################################################

set -e

###############################################################################

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    log_error "Please run as root"
    exit 1
fi

###############################################################################

if [[ "${ENABLE_PROXY:-false}" == "true" ]]; then
  log_warn "Configuring system proxy..."

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
  log_warn "Proxy configuration applied."
else
  log_info "Proxy disabled; skipping configuration."
fi
