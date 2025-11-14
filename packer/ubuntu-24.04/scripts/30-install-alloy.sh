#!/bin/bash
set -euo pipefail

# Grafana Alloy Installation Script
# This script installs Grafana Alloy on Ubuntu 24.04
# Usage: ./install-grafana-alloy.sh
# Env vars: GRAFA_ALLOY_VERSION set to the version you want to install

# Default Alloy version if not provided
ALLOY_VERSION=${GRAFANA_ALLOY_VERSION:-1.11.3}

# Logging setup
readonly LOG_FILE="/var/log/grafana-alloy-install.log"
SCRIPT_NAME="$(basename "$0")"
readonly SCRIPT_NAME

# Initialize log file
sudo mkdir -p "$(dirname "$LOG_FILE")"
sudo touch "$LOG_FILE"
sudo chmod 644 "$LOG_FILE"

# Logging function
log() {
    local level="$1"
    shift
    local message="$*"
    local timestamp
    timestamp="$(date '+%Y-%m-%d %H:%M:%S')"
    echo "[${timestamp}] [${level}] ${message}" | sudo tee -a "$LOG_FILE"
}

log_info() {
    log "INFO" "$@"
}

log_error() {
    log "ERROR" "$@"
}

log_success() {
    log "SUCCESS" "$@"
}

# Error handler
error_exit() {
    log_error "$1"
    exit 1
}

# Main installation process
main() {
    log_info "=========================================="
    log_info "Starting Grafana Alloy Installation"
    log_info "Script: ${SCRIPT_NAME}"
    log_info "Version: ${ALLOY_VERSION}"
    log_info "=========================================="

    # Check if running as root or with sudo
    if [[ $EUID -ne 0 ]]; then
        error_exit "This script must be run as root or with sudo"
    fi

    # Install prerequisites
    log_info "Installing prerequisites..."
    if apt-get update >> "$LOG_FILE" 2>&1 && apt-get install -y wget curl >> "$LOG_FILE" 2>&1; then
        log_success "Prerequisites installed successfully"
    else
        error_exit "Failed to install prerequisites"
    fi

    # Determine architecture
    ARCH=$(dpkg --print-architecture)
    log_info "Detected architecture: ${ARCH}"

    # Construct download URL
    DEB_PACKAGE="alloy-${ALLOY_VERSION}-1.${ARCH}.deb"
    DOWNLOAD_URL="https://github.com/grafana/alloy/releases/download/v${ALLOY_VERSION}/${DEB_PACKAGE}"
    DOWNLOAD_PATH="/tmp/${DEB_PACKAGE}"

    log_info "Download URL: ${DOWNLOAD_URL}"

    # Download the .deb package
    log_info "Downloading Grafana Alloy ${ALLOY_VERSION}..."
    if wget -q --show-progress "${DOWNLOAD_URL}" -O "${DOWNLOAD_PATH}" >> "$LOG_FILE" 2>&1; then
        log_success "Grafana Alloy package downloaded successfully"
    else
        error_exit "Failed to download Grafana Alloy package from ${DOWNLOAD_URL}"
    fi

    # Verify the file exists and has content
    if [[ ! -s "${DOWNLOAD_PATH}" ]]; then
        error_exit "Downloaded file is empty or does not exist"
    fi
    log_info "Package size: $(du -h "${DOWNLOAD_PATH}" | cut -f1)"

    # Install the .deb package
    log_info "Installing Grafana Alloy from .deb package..."
    if dpkg -i "${DOWNLOAD_PATH}" >> "$LOG_FILE" 2>&1; then
        log_success "Grafana Alloy ${ALLOY_VERSION} installed successfully"
    else
        log_error "dpkg installation encountered issues, attempting to fix dependencies..."
        if apt-get install -f -y >> "$LOG_FILE" 2>&1; then
            log_success "Dependencies fixed and Grafana Alloy installed successfully"
        else
            error_exit "Failed to install Grafana Alloy"
        fi
    fi

    # Clean up downloaded package
    log_info "Cleaning up downloaded package..."
    if rm -f "${DOWNLOAD_PATH}"; then
        log_success "Temporary files cleaned up"
    else
        log_info "Warning: Could not remove temporary file ${DOWNLOAD_PATH}"
    fi

    # Verify installation
    log_info "Verifying Grafana Alloy installation..."
    if command -v alloy &> /dev/null; then
        INSTALLED_VERSION=$(alloy --version 2>&1 | head -n 1 || echo "version unknown")
        log_success "Grafana Alloy installed and available in PATH"
        log_info "Installed version: ${INSTALLED_VERSION}"
    else
        error_exit "Grafana Alloy installation verification failed"
    fi

    # Create configuration directory structure
    log_info "Creating Alloy configuration directory structure..."
    ALLOY_CONFIG_DIR="/etc/alloy"
    ALLOY_MODULES_DIR="${ALLOY_CONFIG_DIR}/modules"

    mkdir -p "${ALLOY_MODULES_DIR}"
    if [[ $? -eq 0 ]]; then
        log_success "Configuration directories created at ${ALLOY_CONFIG_DIR}"
    else
        error_exit "Failed to create configuration directories"
    fi

    # Create main configuration file
    log_info "Creating main Alloy configuration file..."
    cat > "${ALLOY_CONFIG_DIR}/config.alloy" << 'EOF'
// Main Alloy Configuration
// This file imports modular components

// Import host metrics collection module
import.file "host_metrics" {
  filename = "/etc/alloy/modules/host_metrics.alloy"
}

// Import Prometheus scrape endpoint module
import.file "prometheus_endpoint" {
  filename = "/etc/alloy/modules/prometheus_endpoint.alloy"
}

// Logging configuration
logging {
  level  = "info"
  format = "logfmt"
}
EOF
    if [[ $? -eq 0 ]]; then
        log_success "Main configuration file created"
    else
        error_exit "Failed to create main configuration file"
    fi

    # Create host metrics module
    log_info "Creating host metrics collection module..."
    cat > "${ALLOY_MODULES_DIR}/host_metrics.alloy" << 'EOF'
// Host Metrics Collection Module
// Collects system metrics using node_exporter-style collectors

prometheus.exporter.unix "host_metrics" {
  // Disable collectors that might not be needed
  disable_collectors = ["wifi", "hwmon"]

  // Filesystem configuration
  filesystem {
    fs_types_exclude     = "^(autofs|binfmt_misc|bpf|cgroup2?|configfs|debugfs|devpts|devtmpfs|fusectl|hugetlbfs|iso9660|mqueue|nsfs|overlay|proc|procfs|pstore|rpc_pipefs|securityfs|selinuxfs|squashfs|sysfs|tracefs)$"
    mount_points_exclude = "^/(dev|proc|run/credentials/.+|sys|var/lib/docker/.+)($|/)"
    mount_timeout        = "5s"
  }
}

// Forward collected metrics to the Prometheus endpoint
prometheus.scrape "host_metrics" {
  targets    = prometheus.exporter.unix.host_metrics.targets
  forward_to = [prometheus.remote_write.metrics_output.receiver]

  job_name = "integrations/node_exporter"

  scrape_interval = "15s"
  scrape_timeout  = "10s"
}
EOF
    if [[ $? -eq 0 ]]; then
        log_success "Host metrics module created"
    else
        error_exit "Failed to create host metrics module"
    fi

    # Create Prometheus endpoint module
    log_info "Creating Prometheus endpoint module..."
    cat > "${ALLOY_MODULES_DIR}/prometheus_endpoint.alloy" << 'EOF'
// Prometheus Endpoint Module
// Exposes collected metrics for Prometheus to scrape
// and optionally pushes to remote Prometheus endpoints

// Remote write endpoints configuration
// Add your remote Prometheus/Mimir/Cortex endpoints here
prometheus.remote_write "metrics_output" {
  // Example remote endpoint (commented out by default)
  // Uncomment and configure to push metrics to remote Prometheus
  /*
  endpoint {
    url = "https://prometheus.example.com/api/v1/write"

    // Optional: Add authentication
    basic_auth {
      username = "your-username"
      password = "your-password"
    }

    // Optional: Add custom headers
    headers = {
      "X-Custom-Header" = "value"
    }

    // Queue configuration
    queue_config {
      capacity             = 10000
      max_shards           = 10
      min_shards           = 1
      max_samples_per_send = 5000
      batch_send_deadline  = "5s"
      min_backoff          = "30ms"
      max_backoff          = "5s"
    }
  }
  */

  // Local endpoint for exposing metrics via HTTP
  // This allows Prometheus to scrape metrics from this Alloy instance
  endpoint {
    url = "http://localhost:12345/api/v1/push"

    // Basic queue configuration
    queue_config {
      capacity             = 10000
      max_shards           = 10
      min_shards           = 1
      max_samples_per_send = 5000
      batch_send_deadline  = "5s"
      min_backoff          = "30ms"
      max_backoff          = "5s"
    }
  }

  // External labels applied to all metrics
  external_labels = {
    cluster = "default"
    env     = "production"
  }
}

// Expose metrics endpoint for Prometheus to scrape
prometheus.exporter.self "alloy_metrics" {
}

prometheus.scrape "alloy_internal" {
  targets    = prometheus.exporter.self.alloy_metrics.targets
  forward_to = [prometheus.remote_write.metrics_output.receiver]

  job_name = "integrations/alloy"

  scrape_interval = "15s"
}
EOF
    if [[ $? -eq 0 ]]; then
        log_success "Prometheus endpoint module created"
    else
        error_exit "Failed to create Prometheus endpoint module"
    fi

    # Set proper permissions
    log_info "Setting configuration file permissions..."
    chown -R alloy:alloy "${ALLOY_CONFIG_DIR}"
    chmod 755 "${ALLOY_CONFIG_DIR}" "${ALLOY_MODULES_DIR}"
    chmod 644 "${ALLOY_CONFIG_DIR}/config.alloy" "${ALLOY_MODULES_DIR}"/*.alloy
    if [[ $? -eq 0 ]]; then
        log_success "Permissions set correctly"
    else
        log_error "Warning: Failed to set some permissions"
    fi

    # Update systemd service to use custom config
    log_info "Configuring systemd service..."
    mkdir -p /etc/systemd/system/alloy.service.d
    cat > /etc/systemd/system/alloy.service.d/override.conf << EOF
[Service]
ExecStart=
ExecStart=/usr/bin/alloy run ${ALLOY_CONFIG_DIR}/config.alloy --storage.path=/var/lib/alloy/data --server.http.listen-addr=0.0.0.0:12345
EOF
    if [[ $? -eq 0 ]]; then
        systemctl daemon-reload >> "$LOG_FILE" 2>&1
        log_success "Systemd service configured to listen on all interfaces"
    else
        log_error "Warning: Failed to configure systemd service"
    fi

    # Enable and start the service
    log_info "Enabling Alloy service..."
    if systemctl enable alloy >> "$LOG_FILE" 2>&1; then
        log_success "Alloy service enabled"
    else
        error_exit "Failed to enable Alloy service"
    fi

    log_info "Starting Alloy service..."
    if systemctl start alloy >> "$LOG_FILE" 2>&1; then
        log_success "Alloy service started"
    else
        error_exit "Failed to start Alloy service"
    fi

    # Wait a moment for service to initialize
    sleep 3

    # Verify service is running
    log_info "Verifying Alloy service status..."
    if systemctl is-active --quiet alloy; then
        log_success "Alloy service is running"
        SERVICE_STATUS=$(systemctl status alloy --no-pager -l | head -n 5)
        log_info "Service status: ${SERVICE_STATUS}"
    else
        log_error "Alloy service failed to start properly"
        systemctl status alloy --no-pager >> "$LOG_FILE" 2>&1
        error_exit "Alloy service verification failed"
    fi

    # Verify metrics endpoint is accessible
    log_info "Verifying metrics endpoint..."
    if curl -s -o /dev/null -w "%{http_code}" http://localhost:12345/metrics | grep -q "200"; then
        log_success "Metrics endpoint is accessible at http://0.0.0.0:12345/metrics"
    else
        log_error "Warning: Metrics endpoint may not be responding yet"
    fi

    log_info "=========================================="
    log_success "Grafana Alloy Installation Completed"
    log_info "Configuration location: ${ALLOY_CONFIG_DIR}"
    log_info "Main config: ${ALLOY_CONFIG_DIR}/config.alloy"
    log_info "Modules: ${ALLOY_MODULES_DIR}/"
    log_info "Service status: Running and enabled"
    log_info "Listening on: 0.0.0.0:12345 (all interfaces)"
    log_info "Log file: ${LOG_FILE}"
    log_info "=========================================="
    log_info ""
    log_info "Service management commands:"
    log_info "  systemctl status alloy     # Check status"
    log_info "  systemctl restart alloy    # Restart service"
    log_info "  journalctl -u alloy -f     # View logs"
    log_info ""
    log_info "Metrics available at: http://<host-ip>:12345/metrics"
}

# Run main function
main "$@"
