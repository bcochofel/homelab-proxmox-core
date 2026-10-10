#!/usr/bin/env bash
# Runs once when the devcontainer is created: installs the repo's pinned
# toolchain from mise.toml/mise.lock. See docs/DEVCONTAINER.md.
set -euo pipefail

# Named volumes are created root-owned.
sudo chown -R "$(id -u):$(id -g)" .venv "$HOME/.claude"

# Same mise version as the workstation; pinned rather than "latest".
# docs/SETUP.md (stage 1) reads it from here, so one bump covers both.
curl -fsSL https://mise.run | MISE_VERSION=v2026.9.18 sh
export PATH="$HOME/.local/bin:$PATH"
# Single quotes on purpose: the line goes into the rc file unexpanded.
# shellcheck disable=SC2016
grep -q 'mise activate' ~/.bashrc 2>/dev/null ||
  echo 'eval "$(~/.local/bin/mise activate bash)"' >>~/.bashrc
# shellcheck disable=SC2016
grep -q 'mise activate' ~/.zshrc 2>/dev/null ||
  echo 'eval "$(~/.local/bin/mise activate zsh)"' >>~/.zshrc
# `mise activate` puts gh's install dir first on PATH; a dir added after it
# stays ahead, so `gh` is the wrapper that runs it as the AI agent.
for rc in ~/.bashrc ~/.zshrc; do
  grep -q '.devcontainer/bin' "$rc" ||
    echo "export PATH=\"$PWD/.devcontainer/bin:\$PATH\"" >>"$rc"
done

# The agent pushes its branches and opens pull requests without a prompt,
# in this clone only: GitHub's rules are the limit (docs/DEVCONTAINER.md).
# Merged into the gitignored local settings, keeping whatever else is there.
local=.claude/settings.local.json
[ -s "$local" ] || echo '{}' >"$local"
jq '(.permissions.allow // []) as $a
    | .permissions.allow = $a + (["Bash(git push *)", "Bash(gh pr create *)"] - $a)' \
  "$local" >"$local.tmp" && mv "$local.tmp" "$local"

mise trust
# Exact versions and checksums from mise.lock, as in CI. MISE_SKIP_BOOTSTRAP
# (devcontainer.json) skips setup:hooks: pre-commit refuses to install with
# core.hooksPath set.
MISE_LOCKED=1 mise install
mise run setup:tflint
# The hooks' environments, for the container-only hooks in
# .devcontainer/git-hooks (core.hooksPath, devcontainer.json).
pre-commit install-hooks
# mise's `_.python.venv` only creates .venv when the path is absent, and
# the named volume mounts it as an empty directory, so create it here.
[ -x .venv/bin/python ] ||
  mise exec -- uv venv --quiet --allow-existing --python "$(mise which python)" .venv
mise run setup:ansible
# The Proxmox MCP server (.mcp.json); the GitHub/Terraform ones came with
# `mise install` above.
mise run mcp:install
