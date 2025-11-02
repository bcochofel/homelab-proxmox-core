#!/usr/bin/env bash
set -euo pipefail

DOCKER_VERSION="${DOCKER_VERSION:-latest}"
DOCKER_USER="${DOCKER_USER:-ubuntu}"

_log() { echo "[$(date -Iseconds)] $*"; }

_log "Installing Docker..."

export DEBIAN_FRONTEND=noninteractive
apt-get update -y
apt-get install -y apt-transport-https ca-certificates curl gnupg lsb-release software-properties-common

install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg

echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
  https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" \
  > /etc/apt/sources.list.d/docker.list

apt-get update -y

if [[ "${DOCKER_VERSION}" == "latest" ]]; then
  apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
else
  apt-get install -y \
    docker-ce="${DOCKER_VERSION}" \
    docker-ce-cli="${DOCKER_VERSION}" \
    containerd.io docker-buildx-plugin docker-compose-plugin
fi

systemctl enable docker
systemctl start docker

if id "${DOCKER_USER}" &>/dev/null; then
  usermod -aG docker "${DOCKER_USER}"
  _log "User ${DOCKER_USER} added to docker group."
fi

docker --version
_log "Docker installation complete."
