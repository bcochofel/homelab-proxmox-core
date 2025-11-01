#!/bin/bash
set -e
echo "=== Installing Grafana Alloy (if enabled) ==="

if [ "${USE_ALLOY}" = "true" ]; then
  apt-get install -y curl tar
  curl -fsSL "https://github.com/grafana/alloy/releases/download/${ALLOY_VERSION}/alloy-linux-amd64.tar.gz" -o /tmp/alloy.tar.gz
  tar -xzf /tmp/alloy.tar.gz -C /usr/local/bin --strip-components=1
  chmod +x /usr/local/bin/alloy

  mkdir -p /etc/alloy
  cat <<EOF >/etc/alloy/config.alloy
logging {
  level = "info"
}

local.file_match "docker_logs" {
  path_targets = ["/var/lib/docker/containers/*/*.log"]
}

loki.source.docker "docker" {
  targets = local.file_match.docker_logs.targets
}

loki.source.journal "journal" {}
loki.source.syslog "syslog" {
  listen_address = "0.0.0.0:1514"
}

prometheus.exporter.docker "metrics" {}

# Prometheus endpoints
EOF

  for ep in ${PROMETHEUS_ENDPOINTS}; do
    echo "prometheus.remote_write \"remote_${ep}\" { endpoint { url = \"${ep}\" } }" >> /etc/alloy/config.alloy
  done

  # Loki endpoints
  for ep in ${LOKI_ENDPOINTS}; do
    echo "loki.write \"remote_${ep}\" { endpoint { url = \"${ep}\" } }" >> /etc/alloy/config.alloy
  done

  cat <<EOF >/etc/systemd/system/alloy.service
[Unit]
Description=Grafana Alloy
After=network-online.target docker.service
Requires=docker.service

[Service]
ExecStart=/usr/local/bin/alloy --config.file=/etc/alloy/config.alloy
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

  systemctl daemon-reload
  systemctl enable alloy
  systemctl start alloy
else
  echo "Alloy not enabled, skipping..."
fi
