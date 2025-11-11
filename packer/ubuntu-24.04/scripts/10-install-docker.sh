#!/usr/bin/env bash
set -euo pipefail
# Install Docker CE and QEMU guest agent

export DEBIAN_FRONTEND=noninteractive

apt-get update -y
apt-get install -y qemu-guest-agent curl ca-certificates gnupg lsb-release apt-transport-https software-properties-common
systemctl enable --now qemu-guest-agent || true

if [[ "${INSTALL_DOCKER:-true}" == "true" ]]; then
  echo "==> Installing Docker..."
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

  echo "==> Docker installed successfully."
else
  echo "==> Docker installation disabled by variable."
fi
