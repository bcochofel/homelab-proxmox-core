#!/bin/bash

###############################################################################
# Ubuntu 26.04 Template Install Elastic Agent
# Purpose: Install Elastic Agent from Elastic's signed tarball with
#          `elastic-agent install` (so Fleet can upgrade it), NOT enrolled,
#          with its service disabled and stopped (see ADR-3)
# Usage: Run this script as root
# Expected env vars:
# INSTALL_ELASTIC_AGENT: If true will install Elastic Agent
# ELASTIC_AGENT_VERSION: Exact version to install (Packer's elastic_agent_version)
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
# Elastic's signing key ("Elasticsearch (Elasticsearch Signing Key)
# <dev_ops@elasticsearch.org>"), as published in Elastic's docs. The
# download is refused if its fingerprint differs.
KEY_FPR="46095ACC8548582C1A2699A9D27D666CD88E42B4" # gitleaks:allow (public key fingerprint, not a secret)
INSTALL_DIR=/opt/Elastic/Agent

case "$(uname -m)" in
  x86_64) ARCH=x86_64 ;;
  aarch64) ARCH=arm64 ;;
  *)
    log_error "Unsupported architecture: $(uname -m)"
    exit 1
    ;;
esac

NAME="elastic-agent-${VERSION}-linux-${ARCH}"
URL="https://artifacts.elastic.co/downloads/beats/elastic-agent/${NAME}.tar.gz"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

log_info "Downloading ${NAME}.tar.gz and its signature..."
curl -fsSL "$URL" -o "${WORK}/${NAME}.tar.gz"
curl -fsSL "${URL}.sha512" -o "${WORK}/${NAME}.tar.gz.sha512"
curl -fsSL "${URL}.asc" -o "${WORK}/${NAME}.tar.gz.asc"
curl -fsSL https://artifacts.elastic.co/GPG-KEY-elasticsearch -o "${WORK}/elastic.asc"

GOT_FPR="$(gpg --show-keys --with-colons "${WORK}/elastic.asc" 2>/dev/null | awk -F: '/^fpr:/{print $10; exit}')"
if [ "$GOT_FPR" != "$KEY_FPR" ]; then
  log_error "Elastic signing key fingerprint mismatch: got '${GOT_FPR}', expected '${KEY_FPR}'."
  exit 1
fi
gpg --dearmor --yes -o "${WORK}/elastic.gpg" "${WORK}/elastic.asc"

log_info "Verifying the tarball's signature and checksum..."
gpgv --keyring "${WORK}/elastic.gpg" "${WORK}/${NAME}.tar.gz.asc" "${WORK}/${NAME}.tar.gz"
(cd "$WORK" && sha512sum -c "${NAME}.tar.gz.sha512")

tar -xzf "${WORK}/${NAME}.tar.gz" -C "$WORK"

# `install` without --url installs into /opt/Elastic/Agent, creates
# elastic-agent.service and starts it standalone (the tarball's default
# elastic-agent.yml; its output is unreachable, so it ships nothing). It's
# stopped and disabled right below. A tarball install, unlike the DEB, can
# be upgraded from Fleet once a later Ansible playbook enrolls it.
log_info "Installing Elastic Agent ${VERSION} to ${INSTALL_DIR}..."
"${WORK}/${NAME}/elastic-agent" install --non-interactive

# Installed but inert: not enrolled anywhere, and nothing starts it. A
# later Ansible playbook enrolls it (`elastic-agent enroll`) and enables
# the service once the Elastic stack exists.
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

if ! /usr/bin/elastic-agent version --binary-only | grep -qF "${VERSION} "; then
  log_error "Installed elastic-agent isn't ${VERSION}: $(/usr/bin/elastic-agent version --binary-only)"
  exit 1
fi

log_info "Elastic Agent ${VERSION} installed in ${INSTALL_DIR}, not enrolled; service disabled and stopped."
