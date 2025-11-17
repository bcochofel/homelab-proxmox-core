#!/bin/bash
set -euo pipefail

# This scripts creates a systemd service that will initialize AIDE on first boot
# on the cloned VM.
# It also enables rkhunter, chkrootkit, and lynis services

# Create directory for our firstboot scripts
#mkdir -p /etc/firstboot.d
#
## Create the AIDE initialization script
#cat << 'EOF' > /etc/firstboot.d/aide-firstboot.sh
##!/usr/bin/env bash
#set -e
#
## If AIDE baseline already exists, skip
#if [ -f /var/lib/aide/aide.db ]; then
#    echo "AIDE baseline already exists. Skipping."
#    exit 0
#fi
#
#echo "Running AIDE baseline initialization..."
#
## Generate baseline
#aideinit
#
## Promote the new baseline
#if [ -f /var/lib/aide/aide.db.new ]; then
#    mv /var/lib/aide/aide.db.new /var/lib/aide/aide.db
#    chmod 600 /var/lib/aide/aide.db
#fi
#
## Enable AIDE daily timer
#systemctl enable aide-check.timer || true
#
#echo "AIDE baseline initialization completed."
#EOF
#
#chmod +x /etc/firstboot.d/aide-firstboot.sh
#
## Create a systemd service to run the script ONCE
#cat << 'EOF' > /etc/systemd/system/aide-firstboot.service
#[Unit]
#Description=Run AIDE baseline on first non-template boot
#After=multi-user.target
#
#[Service]
#Type=oneshot
#ExecStart=/etc/firstboot.d/aide-firstboot.sh
#RemainAfterExit=no
#
#[Install]
#WantedBy=multi-user.target
#EOF
#
##!/usr/bin/env bash
#set -e
#
## Create directory for our firstboot scripts
#mkdir -p /etc/firstboot.d
#
## Create the AIDE initialization script
#cat << 'EOF' > /etc/firstboot.d/aide-firstboot.sh
##!/usr/bin/env bash
#set -e
#
## If AIDE baseline already exists, skip
#if [ -f /var/lib/aide/aide.db ]; then
#    echo "AIDE baseline already exists. Skipping."
#    exit 0
#fi
#
#echo "Running AIDE baseline initialization..."
#
## Generate baseline
#aideinit
#
## Promote the new baseline
#if [ -f /var/lib/aide/aide.db.new ]; then
#    mv /var/lib/aide/aide.db.new /var/lib/aide/aide.db
#    chmod 600 /var/lib/aide/aide.db
#fi
#
## Enable AIDE daily timer
#systemctl enable aide-check.timer || true
#
#echo "AIDE baseline initialization completed."
#EOF
#
#chmod +x /etc/firstboot.d/aide-firstboot.sh
#
## Create a systemd service to run the script ONCE
#cat << 'EOF' > /etc/systemd/system/aide-firstboot.service
#[Unit]
#Description=Run AIDE baseline on first non-template boot
#After=multi-user.target
#
#[Service]
#Type=oneshot
#ExecStart=/etc/firstboot.d/aide-firstboot.sh
#RemainAfterExit=no
#
#[Install]
#WantedBy=multi-user.target
#EOF

# RKHUNTER
systemctl enable rkhunter.timer
# CHKROOTKIT
systemctl enable chkrootkit.timer
# LYNIS
systemctl enable lynis.timer
# AIDE
#systemctl enable aide-firstboot.service
