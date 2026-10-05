#!/usr/bin/env bash
# Runs once when the devcontainer is created: installs the repo's pinned
# toolchain from mise.toml/mise.lock. See docs/DEVCONTAINER.md.
set -euo pipefail

# Named volumes are created root-owned.
sudo chown -R "$(id -u):$(id -g)" .venv "$HOME/.claude"

# Same mise version as the workstation; pinned rather than "latest".
curl -fsSL https://mise.run | MISE_VERSION=v2026.9.18 sh
export PATH="$HOME/.local/bin:$PATH"
grep -q 'mise activate' ~/.bashrc 2>/dev/null ||
  echo 'eval "$(~/.local/bin/mise activate bash)"' >>~/.bashrc
grep -q 'mise activate' ~/.zshrc 2>/dev/null ||
  echo 'eval "$(~/.local/bin/mise activate zsh)"' >>~/.zshrc

mise trust
# Exact versions and checksums from mise.lock, as in CI. MISE_SKIP_BOOTSTRAP
# (devcontainer.json) skips git-hook setup: commits are made from the host.
MISE_LOCKED=1 mise install
mise run setup:tflint
mise run setup:ansible
# The Proxmox MCP server (.mcp.json); the GitHub/Terraform ones came with
# `mise install` above.
mise run mcp:install
