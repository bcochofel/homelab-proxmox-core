#!/bin/bash

###############################################################################
# Ubuntu 26.04 Template Install Elastic Agent
# Purpose: Install Elastic Agent from Elastic's APT repo, pinned and held,
#          NOT enrolled, with its service disabled and stopped (see ADR-3)
# Usage: Run this script as root
# Expected env vars:
# INSTALL_ELASTIC_AGENT: If true will install Elastic Agent
# ELASTIC_AGENT_VERSION: Exact version to install (e.g. 9.5.4)
###############################################################################

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

if [ "$EUID" -ne 0 ]; then
    log_error "Please run as root"
    exit 1
fi

###############################################################################

if [[ "${INSTALL_ELASTIC_AGENT:-true}" != "true" ]]; then
  log_warn "Elastic Agent installation disabled by variable."
  exit 0
fi

VERSION="${ELASTIC_AGENT_VERSION:?ELASTIC_AGENT_VERSION must be set}"
MAJOR="${VERSION%%.*}"
# Elastic's signing key ("Elasticsearch (Elasticsearch Signing Key)
# <dev_ops@elasticsearch.org>"), as published in Elastic's docs. The
# download is refused if its fingerprint differs.
KEY_FPR="46095ACC8548582C1A2699A9D27D666CD88E42B4" # gitleaks:allow (public key fingerprint, not a secret)
KEYRING=/etc/apt/keyrings/elastic.gpg

export DEBIAN_FRONTEND=noninteractive

log_info "Adding Elastic's APT repository (${MAJOR}.x)..."
mkdir -p /etc/apt/keyrings
KEY_TMP="$(mktemp)"
curl -fsSL https://artifacts.elastic.co/GPG-KEY-elasticsearch -o "$KEY_TMP"
GOT_FPR="$(gpg --show-keys --with-colons "$KEY_TMP" 2>/dev/null | awk -F: '/^fpr:/{print $10; exit}')"
if [ "$GOT_FPR" != "$KEY_FPR" ]; then
  log_error "Elastic signing key fingerprint mismatch: got '${GOT_FPR}', expected '${KEY_FPR}'."
  exit 1
fi
gpg --dearmor --yes -o "$KEYRING" "$KEY_TMP"
rm -f "$KEY_TMP"
chmod a+r "$KEYRING"

echo "deb [arch=$(dpkg --print-architecture) signed-by=${KEYRING}] https://artifacts.elastic.co/packages/${MAJOR}.x/apt stable main" \
  > "/etc/apt/sources.list.d/elastic-${MAJOR}.x.list"

apt-get update -y

log_info "Installing elastic-agent=${VERSION}..."
apt-get install -y "elastic-agent=${VERSION}"

# Upgrades are deliberate (bump elastic_agent_version and rebuild, or let
# Ansible upgrade the package later), never a side effect of
# unattended-upgrades or a routine `apt upgrade`.
apt-mark hold elastic-agent

# Installed but inert: not enrolled anywhere, and nothing starts it. A
# later Ansible playbook enrolls it (`elastic-agent enroll`, the DEB way)
# and enables the service once the Elastic stack exists.
log_info "Disabling and stopping the elastic-agent service..."
systemctl disable --now elastic-agent.service

if systemctl is-enabled --quiet elastic-agent.service; then
  log_error "elastic-agent.service is still enabled."
  exit 1
fi
if systemctl is-active --quiet elastic-agent.service; then
  log_error "elastic-agent.service is still running."
  exit 1
fi

INSTALLED="$(dpkg-query -W -f='${Version}' elastic-agent)"
if [ "$INSTALLED" != "$VERSION" ]; then
  log_error "Installed elastic-agent ${INSTALLED}, expected ${VERSION}."
  exit 1
fi

log_info "Elastic Agent ${INSTALLED} installed, held, not enrolled; service disabled and stopped."
