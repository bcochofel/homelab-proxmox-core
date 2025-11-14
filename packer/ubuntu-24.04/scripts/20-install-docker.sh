#!/bin/bash

###############################################################################
# Ubuntu 24.04 Template Install Docker
# Purpose: Install Docker and Docker Compose
# Usage: Run this script as root
# Expected env vars:
# INSTALL_DOCKER: If true will install Docker
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

log_info "Starting Docker Installation..."

export DEBIAN_FRONTEND=noninteractive

apt-get update -y
apt-get install -y qemu-guest-agent curl ca-certificates gnupg lsb-release apt-transport-https software-properties-common
systemctl enable --now qemu-guest-agent || true

if [[ "${INSTALL_DOCKER:-true}" == "true" ]]; then
  log_info "Installing Docker..."
  mkdir -p /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
  chmod a+r /etc/apt/keyrings/docker.gpg || true

  echo \
    "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
    https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo \"$VERSION_CODENAME\") stable" \
    > /etc/apt/sources.list.d/docker.list

  apt-get update -y
  apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin || true
  systemctl enable docker || true

  if id -u ubuntu >/dev/null 2>&1; then
    usermod -aG docker ubuntu || true
  fi

  log_info "Docker installed successfully."
else
  log_warn "Docker installation disabled by variable."
fi
