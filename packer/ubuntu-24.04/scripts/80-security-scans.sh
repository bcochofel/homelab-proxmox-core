#!/bin/bash
set -euo pipefail

# RKHUNTER
systemctl enable rkhunter.timer

# CHKROOTKIT
systemctl enable chkrootkit.timer

# LYNIS
systemctl enable lynis.timer

# AIDE - Enable initialization service (runs once on first boot of cloned VM)
systemctl enable aide-init.service

# AIDE - Enable daily check timer (runs after DB is initialized)
systemctl enable aide-check.timer
