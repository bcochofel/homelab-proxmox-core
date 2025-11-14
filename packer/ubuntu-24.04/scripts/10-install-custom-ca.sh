#!/bin/bash

###############################################################################
# Ubuntu 24.04 Template Installs CUSTOM CA
# Purpose: Install Custm CA certificates
# Usage: Run this script as root
# Expects:
#   - Certificates must be placed in the repository's custom-ca/ directory.
#   - Files with extensions .crt or .pem will be copied to
#     /usr/local/share/ca-certificates/custom/ and registered with
#     update-ca-certificates.
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

log_info "Installing custom CA certificates (if any)..."

SRC_DIR="/tmp/custom-ca"
DEST_DIR="/usr/local/share/ca-certificates/custom"

# Packer will upload the custom-ca folder automatically if it exists in the repo.
if [ ! -d "${SRC_DIR}" ]; then
  log_warn "No custom CA directory found at ${SRC_DIR}; skipping."
  exit 0
fi

# Create destination directory if missing
mkdir -p "${DEST_DIR}"

# Copy valid certificate files
CERT_COUNT=0
for cert in "${SRC_DIR}"/*.{crt,pem}; do
  if [ -f "$cert" ]; then
    cp -f "$cert" "${DEST_DIR}/"
    chmod 644 "${DEST_DIR}/$(basename "$cert")"
    echo "  -> Added $(basename "$cert")"
    CERT_COUNT=$((CERT_COUNT + 1))
  fi
done

if [ "${CERT_COUNT}" -eq 0 ]; then
  log_warn "No .crt or .pem files found in ${SRC_DIR}; nothing to import."
  exit 0
fi

# Update system CA store
log_warn "Updating CA trust store..."
update-ca-certificates

# Verify the certs were added
log_warn "Verifying installed CAs:"
ls -1 /etc/ssl/certs/custom_* || true

log_warn "${CERT_COUNT} custom CA certificate(s) installed successfully."
