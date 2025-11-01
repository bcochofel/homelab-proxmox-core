#!/bin/bash
set -e
echo "=== Installing Docker ==="
apt-get update -y
apt-get install -y docker.io
systemctl enable docker

mkdir -p /etc/systemd/system/docker.service.d
if [ "${USE_PROXY}" = "true" ]; then
  echo "[Service]
Environment=\"HTTP_PROXY=${HTTP_PROXY}\" \"HTTPS_PROXY=${HTTPS_PROXY}\" \"NO_PROXY=${NO_PROXY}\"" \
    > /etc/systemd/system/docker.service.d/http-proxy.conf

  mkdir -p /root/.docker
  cat <<EOF > /root/.docker/config.json
{
  "proxies": {
    "default": {
      "httpProxy": "${HTTP_PROXY}",
      "httpsProxy": "${HTTPS_PROXY}",
      "noProxy": "${NO_PROXY}"
    }
  }
}
EOF
fi

systemctl daemon-reexec
systemctl daemon-reload
systemctl restart docker
