# Devcontainer

A container for running the AI agent (Claude Code) against this repo with **only the
read-only credentials**. It turns the soft boundary from
[`CREDENTIALS.md`](CREDENTIALS.md) step 6 into a hard one: a guardrail
that holds by construction, as Google's
[*AI engineering for reliable operations*](https://sre.google/resources/practices-and-processes/ai-engineering-reliable-operations/)
recommends (see the README's
[Why it's built this way](../README.md#why-its-built-this-way)).

## Soft and hard boundaries

The AI agent must only ever use the `ai-agent` identity: it can read and
investigate, never change infrastructure. There are two ways to enforce
that.

**Soft boundary: the AI agent on WSL.** It runs as your own OS
user, on the same filesystem as your age key and `~/.secrets/homelab.yaml`.
What keeps it to read-only is `.claude/settings.json`:

- its `env` block points SOPS and Ansible at the `ai-agent` key, so the
  commands it runs can only decrypt `homelab-ro.yaml`;
- its deny rules block reading your key, `~/.secrets/` and the encrypted
  inventory, every decrypting `sops` subcommand, and the read-write mise
  tasks;
- its ask rules make you approve every `apply`, `packer build` and
  `ansible-playbook`.

Those rules match tool calls and command patterns, not intent. A command
nobody anticipated, for example a script that copies your key elsewhere,
isn't matched by any rule. The files are still there; only the policy
keeps the AI agent away from them.

**Hard boundary: the AI agent in this devcontainer.** Your age key,
`~/.secrets/homelab.yaml` and the Docker socket are never mounted into the
container. The read-write credentials don't exist inside it, so no command,
anticipated or not, can use them. `.claude/settings.json` still applies
inside, as a second layer.

| | Soft (WSL) | Hard (devcontainer) |
| --- | --- | --- |
| Your age key | On disk, blocked by deny rules | Not present |
| `~/.secrets/homelab.yaml` | On disk, blocked by deny rules | Not present |
| `ai-agent` key and `homelab-ro.yaml` | Readable | Readable (mounted read-only) |
| Docker socket | Available | Not present |
| `tofu init -backend=false`, `tofu validate` | Works | Works |
| `packer:build`, `tofu:init`, `tofu:plan`, `tofu:apply` | Fail: the key can't decrypt their file (the ones that change anything are also denied) | Fail: their file doesn't exist |
| Inventory secrets (Ansible) | `ai-agent` key can't decrypt them | `ai-agent` key can't decrypt them |
| MCP servers ([`CREDENTIALS.md`](CREDENTIALS.md) step 8) | Available | Available (same `.mcp.json`) |

Use the devcontainer whenever the AI agent works on its own for a while;
the soft boundary is fine for short, supervised sessions on WSL.

## What's inside

| Present | Not present |
| --- | --- |
| The repo (your working copy) | Your age key (`~/.config/sops/age/bcochofel.txt`) |
| The `ai-agent` age key, read-only | `~/.secrets/homelab.yaml` (read-write credentials) |
| `~/.secrets/homelab-ro.yaml`, read-only | The Docker socket |
| The repo's toolchain from `mise.toml`/`mise.lock` | Your shell environment and dotfiles |
| Claude Code (CLI and VS Code extension) | |
| The MCP servers from `.mcp.json` (Proxmox, GitHub, Terraform) | |

The container runs Ubuntu 26.04, the same release as the VMs, from a
pinned image. The configuration is `.devcontainer/devcontainer.json`; the
toolchain and the MCP servers are installed by
`.devcontainer/post-create.sh`.

## Prerequisites

- **Rancher Desktop** on Windows with the container engine set to
  **dockerd (moby)**, and *WSL Integration* enabled for your Ubuntu
  distribution. In *Preferences → Application → Behavior*, turn on
  *Automatically start at login* and *Start in the background*, so the
  engine is running whenever you need it.
- **VS Code** with the **WSL** and **Dev Containers** extensions, with the
  repo opened from WSL (`code .` in the repo directory).
- On the WSL side, both files the container mounts must exist
  ([`CREDENTIALS.md`](CREDENTIALS.md) steps 4 and 5):
  - `~/.config/sops/age/ai-agent.txt`
  - `~/.secrets/homelab-ro.yaml`

## Starting it

The devcontainer **never starts on its own**. Opening the repo in VS Code
opens it on WSL (soft boundary); you switch to the container explicitly.

1. Make sure the engine is up. After a Windows login Rancher Desktop takes
   a minute or so; from WSL, `docker version` must show a *Server*
   section. If you open the container before that, Dev Containers fails
   with a "cannot connect to Docker" error: wait and retry.
2. Open the repo from WSL. VS Code shows a notification offering to reopen
   the folder in a container: accept it, or run *Command Palette → Dev
   Containers: Reopen in Container*.
3. The first time, the image is downloaded and `post-create.sh` installs
   the toolchain (a few minutes). Then sign in to Claude Code once, from the
   Claude Code panel or by running `claude` in the container's terminal.
   The login is kept in a volume, so rebuilds don't ask again. Approve the
   three project MCP servers when Claude Code asks (or with `/mcp`), then
   check them with `claude mcp list`: all three show *Connected*.

Where you are is shown at the bottom-left of the VS Code window:
*Dev Container: homelab-proxmox-core (ai-agent)* is the hard boundary,
*WSL: Ubuntu* is the soft one.

Afterwards:

- **Reopening:** *File → Open Recent* lists the repo twice; the entry
  tagged *[Dev Container]* opens straight into the container.
- **Back to WSL:** *Dev Containers: Reopen Folder in WSL*.
- **Stopping:** closing the window stops the container. Reopening reuses
  it, so the toolchain isn't reinstalled.
- **Rebuilding:** *Dev Containers: Rebuild Container* after a change to
  `.devcontainer/` or `mise.toml`; it runs `post-create.sh` again.

Keep committing and pushing **from WSL**, not from the container: the
container doesn't install git hooks, so pre-commit and commitlint only
run on the host.

## Prove the boundary

Run these in the container's terminal after the first start, and after
every rebuild. Anything other than the expected result means a credential
is wider than intended, or the agent's tooling is broken.

```bash
mise run boundary:check
```

**Expect:** every line `ok`. It runs the same checks as on WSL
([`CREDENTIALS.md`](CREDENTIALS.md) step 7: no exported credentials, the
`ai-agent` key opens `homelab-ro.yaml` and nothing else, no OpenTofu key in
it, the `ai-agent` Proxmox token can't write), plus a `== devcontainer`
section: your age key, `homelab.yaml` and the Docker socket aren't in the
container, and `SOPS_AGE_KEY_FILE` is the `ai-agent` key. The files that
aren't in the container show as `not present`, which is what you want.

Then check that the agent's work runs there:

```bash
cd terraform && tofu init -backend=false && tofu validate && cd ..            # Success
cd ansible && ansible-lint && ansible-playbook playbooks/site.yml --syntax-check && cd ..   # both pass

mise run tofu:plan      # fails: no ~/.secrets/homelab.yaml, and no key for it
claude mcp list         # proxmox, github and terraform: Connected
```

## Limits

- **The working copy is shared.** The repo is mounted read-write, `.git`
  included, and you run its tasks and hooks on WSL with the full
  credentials. Review what the AI agent changed in the container
  (`git status`, `git diff`, and anything under `.git/hooks`) before
  running it on WSL.
- **One user path:** `.claude/settings.json` points `SOPS_AGE_KEY_FILE` at
  `/home/bcochofel/.config/sops/age/ai-agent.txt`, and the container
  mounts the key at that same path. A different home directory means
  changing both.
