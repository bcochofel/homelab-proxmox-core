#!/usr/bin/env bash
set -euo pipefail
#
# Import any custom CA certificates into system trust store.
# Certificates must be placed in the repository's custom-ca/ directory.
# Files with extensions .crt or .pem will be copied to
# /usr/local/share/ca-certificates/custom/ and registered with update-ca-certificates.
#

echo "==> Installing custom CA certificates (if any)..."

SRC_DIR="/tmp/custom-ca"
DEST_DIR="/usr/local/share/ca-certificates/custom"

# Packer will upload the custom-ca folder automatically if it exists in the repo.
if [ ! -d "${SRC_DIR}" ]; then
  echo "No custom CA directory found at ${SRC_DIR}; skipping."
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
  echo "No .crt or .pem files found in ${SRC_DIR}; nothing to import."
  exit 0
fi

# Update system CA store
echo "Updating CA trust store..."
update-ca-certificates

# Verify the certs were added
echo "==> Verifying installed CAs:"
ls -1 /etc/ssl/certs/custom_* || true

echo "==> ${CERT_COUNT} custom CA certificate(s) installed successfully."
