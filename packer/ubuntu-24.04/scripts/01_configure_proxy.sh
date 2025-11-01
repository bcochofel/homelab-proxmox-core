#!/bin/bash
set -e
echo "=== Configuring system proxy (if enabled) ==="

if [ "${USE_PROXY}" = "true" ]; then
  echo "Applying proxy settings..."
  cat <<EOF | tee -a /etc/environment
http_proxy=${HTTP_PROXY}
https_proxy=${HTTPS_PROXY}
no_proxy=${NO_PROXY}
EOF

  echo "Acquire::http::Proxy \"${HTTP_PROXY}\";" > /etc/apt/apt.conf.d/95proxies
  echo "Acquire::https::Proxy \"${HTTPS_PROXY}\";" >> /etc/apt/apt.conf.d/95proxies
else
  echo "Proxy not enabled, skipping..."
fi
