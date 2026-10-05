# Devcontainer

A container for running Claude Code against this repo with **only the
read-only credentials**. It's the hard version of the boundary in
[`CREDENTIALS.md`](CREDENTIALS.md) step 7: there, Claude Code runs as your
OS user and deny rules keep it away from your own age key; here, your key
simply isn't in the container.

## What's inside

| Present | Not present |
| --- | --- |
| The repo (your working copy) | Your age key (`~/.config/sops/age/keys.txt`) |
| The `ai-agent` age key, read-only | `~/.secrets/homelab.yaml` (read-write credentials) |
| `~/.secrets/homelab-ro.yaml`, read-only | The Docker socket |
| The repo's toolchain from `mise.toml`/`mise.lock` | Your shell environment and dotfiles |
| Claude Code | |

So inside the container `mise run tofu:plan-ro` works, while
`mise run tofu:plan`, `tofu:apply` and `packer:build` can't even decrypt
their credentials, and Ansible can't open the inventory secrets. The
agent's Ansible work stays at `ansible-lint` and `--syntax-check`.

The configuration is `.devcontainer/devcontainer.json`; the toolchain is
installed by `.devcontainer/post-create.sh`.

## Prerequisites

- **Rancher Desktop** on Windows with the container engine set to
  **dockerd (moby)**, and *WSL Integration* enabled for your Ubuntu
  distribution. Check from WSL: `docker version` shows a server.
- **VS Code** with the **WSL** and **Dev Containers** extensions, with the
  repo opened from WSL (`code .` in the repo directory).
- On the WSL side, both files the container mounts must exist
  ([`CREDENTIALS.md`](CREDENTIALS.md) steps 4 and 5):
  - `~/.config/sops/age/ai-agent.txt`
  - `~/.secrets/homelab-ro.yaml`

## Open it

1. In VS Code: *Command Palette → Dev Containers: Reopen in Container*.
   The first build downloads the image and installs the toolchain (a few
   minutes); later starts reuse it.
2. In the container's terminal, sign in to Claude Code once: run `claude`.
   The login is kept in a volume, so rebuilds don't ask again.

Keep committing and pushing **from WSL**, not from the container: the
container doesn't install git hooks, so pre-commit and commitlint only
run on the host.

## Prove the boundary

Run these in the container's terminal after the first start. Each must
behave as described; anything else means a credential is wider than
intended.

```bash
ls ~/.config/sops/age/                         # no keys.txt
ls ~/.secrets/                                 # homelab-ro.yaml only
env | grep -E 'PKR_VAR|TF_VAR|TF_TOKEN'        # nothing

sops -d ~/.secrets/homelab-ro.yaml >/dev/null && echo ok   # ok
mise run tofu:plan-ro                                      # succeeds

mise run tofu:plan                     # fails: no ~/.secrets/homelab.yaml
mise run packer:build                  # fails: same

cd ansible && ansible-lint && ansible-playbook playbooks/site.yml --syntax-check   # pass
```

## Limits

- **MCP servers:** the GitHub and Terraform servers in
  [`CREDENTIALS.md`](CREDENTIALS.md) step 9 run with `docker run`, and the
  container has no Docker socket, so they aren't available inside it. Use
  them from Claude Code on WSL, or add their binaries to the image later.
- **One user path:** `.claude/settings.json` points `SOPS_AGE_KEY_FILE` at
  `/home/bcochofel/.config/sops/age/ai-agent.txt`, and the container
  mounts the key at that same path. A different home directory means
  changing both.
