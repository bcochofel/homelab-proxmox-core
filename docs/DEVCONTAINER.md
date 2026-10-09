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
`~/.secrets/homelab.yaml`, your ssh-agent, your git credentials and the
Docker socket are never available in the container. The read-write credentials don't exist inside it, so no command,
anticipated or not, can use them. `.claude/settings.json` still applies
inside, as a second layer.

| | Soft (WSL) | Hard (devcontainer) |
| --- | --- | --- |
| Your age key | On disk, blocked by deny rules | Not present |
| `~/.secrets/homelab.yaml` | On disk, blocked by deny rules | Not present |
| `ai-agent` key and `homelab-ro.yaml` | Readable | Readable (mounted read-only) |
| Docker socket | Available | Not present |
| Your ssh-agent and git credentials | Available: `git push` and `gh` act as you, after you approve them | Not present |
| GitHub identity | Yours | `bcochofel-ai-agent`, the AI agent's machine user ([`CREDENTIALS.md`](CREDENTIALS.md) step 9) |
| `tofu init -backend=false`, `tofu validate` | Works | Works |
| `packer:build`, `tofu:init`, `tofu:plan`, `tofu:apply` | Fail: the key can't decrypt their file (the ones that change anything are also denied) | Fail: their file doesn't exist |
| Inventory secrets (Ansible) | `ai-agent` key can't decrypt them | `ai-agent` key can't decrypt them |
| MCP servers ([`CREDENTIALS.md`](CREDENTIALS.md) step 8) | Available | Available (same `.mcp.json`) |

Use the devcontainer whenever the AI agent works on its own for a while;
the soft boundary is fine for short, supervised sessions on WSL.

## What's inside

| Present | Not present |
| --- | --- |
| The AI agent's own clone of the repo, in a Docker volume | Your WSL working copy |
| | Your age key (`~/.config/sops/age/bcochofel.txt`) |
| The `ai-agent` age key, read-only | `~/.secrets/homelab.yaml` (read-write credentials) |
| `~/.secrets/homelab-ro.yaml`, read-only | The Docker socket |
| `~/.secrets/ai-agent-git.yaml`, read-only | Your ssh-agent (`SSH_AUTH_SOCK` is blank) |
| The repo's toolchain from `mise.toml`/`mise.lock` | VS Code's git credential helper and askpass |
| Claude Code (CLI and VS Code extension) | Your shell environment and dotfiles |
| The MCP servers from `.mcp.json` (Proxmox, GitHub, Terraform) | |
| git and `gh` as `bcochofel-ai-agent` | |

The container runs Ubuntu 26.04, the same release as the VMs, from a
pinned image. The configuration is `.devcontainer/devcontainer.json`; the
toolchain and the MCP servers are installed by
`.devcontainer/post-create.sh`.

## Prerequisites

- **A Docker runtime**, which the Dev Containers extension needs to build
  and run the container.
- **VS Code** with the **WSL** and **Dev Containers** extensions, started
  from WSL.
- On the WSL side, the files the container mounts must exist
  ([`CREDENTIALS.md`](CREDENTIALS.md) steps 4 and 5):
  - `~/.config/sops/age/ai-agent.txt`
  - `~/.secrets/homelab-ro.yaml`
  - `~/.secrets/ai-agent-git.yaml` (step 9)

## Two clones

The AI agent never works in your WSL working copy. It has its own clone,
in a Docker volume that only the container sees:

- **The AI agent's clone (the container):** it branches, commits, pushes
  and opens pull requests there, as `bcochofel-ai-agent`. It owns that
  clone entirely, `.git/config` and `.git/hooks` included.
- **Your clone (WSL):** you `git pull` `main` there after merging, and run
  every credentialed task from it (`mise run tofu:*`, `ansible:site`,
  `sops`, `secrets:check`). You only ever run reviewed, merged code with
  your credentials.

A shared working copy would let anything the agent wrote (a `mise.toml`
task, a playbook, a git hook, a `.git/config` key) run with your
credentials the next time you used it on WSL. Two clones remove that
path; the pull request is the only way its work reaches you.

## Starting it

The devcontainer **never starts on its own**.

1. Make sure Docker is running: from WSL, `docker version` must show a
   *Server* section. Otherwise Dev Containers fails with a "cannot connect
   to Docker" error.
2. In VS Code started from WSL: *Command Palette → Dev Containers: Clone
   Repository in Container Volume...*, then the repository's HTTPS URL,
   `https://github.com/BCochofelHomelab/homelab-proxmox-core`. VS Code
   clones it into a new volume and builds the container from the clone's
   `.devcontainer/`, so it uses the configuration on the branch it clones
   (`main`).
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

- **Reopening:** *File → Open Recent* lists the clone, tagged
  *[Dev Container]*; or the *Remote Explorer* view, under *Dev Volumes*.
- **Back to your clone:** open a new VS Code window on WSL (`code .` in
  your repo directory).
- **Stopping:** closing the window stops the container. Reopening reuses
  it and its volume, so neither the clone nor the toolchain is redone.
- **Rebuilding:** *Dev Containers: Rebuild Container* after a change to
  `.devcontainer/` or `mise.toml` (pulled into the agent's clone); it runs
  `post-create.sh` again and keeps the clone.

## git and GitHub in the container

The AI agent commits, pushes its branches and opens pull requests from
the container as `bcochofel-ai-agent`
([`CREDENTIALS.md`](CREDENTIALS.md) step 9). You review and merge them on
GitHub ([`GITHUB.md`](GITHUB.md)).

- **Identity:** `devcontainer.json` sets git's config through
  `GIT_CONFIG_*` variables, which take precedence over every config file:
  commits are authored by `bcochofel-ai-agent`, and an SSH remote is
  rewritten to HTTPS: it never pushes with an SSH key
  ([`GITHUB.md`](GITHUB.md#why-https-never-ssh)).
- **Credentials:** an empty `credential.helper` drops VS Code's forwarding
  helper, and `.devcontainer/bin/git-credential-ai-agent` is the only one
  left: it decrypts the agent's token for github.com, per request, and
  never stores it. `gh` is `.devcontainer/bin/gh`, a wrapper that passes
  the same token to the one `gh` process as `GH_TOKEN`. `SSH_AUTH_SOCK` is
  blank, so your SSH keys aren't reachable.
- **Hooks:** pre-commit and commitlint run from the container-only hooks
  in `.devcontainer/git-hooks` (`core.hooksPath`). CI runs the same
  checks on every pull request.

In your WSL clone you commit and push as usual, as yourself.

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
it, the `ai-agent` Proxmox token can't write, `.git/config` sets nothing
that runs code, CODEOWNERS names neither the machine user nor `sre-team`),
plus a `== devcontainer`
section: your age key, `homelab.yaml` and the Docker socket aren't in the
container, and `SOPS_AGE_KEY_FILE` is the `ai-agent` key. A second section
checks git and GitHub:

- no ssh-agent, and the agent's credential helper is the only one;
- commits authored by `bcochofel-ai-agent`, hooks from
  `.devcontainer/git-hooks`;
- the working copy is a volume clone, not a bind mount of your WSL one;
- `gh` is the wrapper in bash and zsh, and both `gh` and a
  `git push --dry-run` authenticate as `bcochofel-ai-agent`;
- `main`'s rules, as GitHub applies them to the machine user, require a
  code owner's approval;
- a push of a commit touching `.github/workflows/` is refused. The check
  builds that commit without touching the working copy and pushes it to
  a `boundary-check-workflows` branch; if GitHub ever accepts it, the
  check deletes the branch and fails.
 The files that aren't in the
container show as `not present`, which is what you want.

Then check that the agent's work runs there:

```bash
cd terraform && tofu init -backend=false && tofu validate && cd ..            # Success
cd ansible && ansible-lint && ansible-playbook playbooks/site.yml --syntax-check && cd ..   # both pass

mise run tofu:plan      # fails: no ~/.secrets/homelab.yaml, and no key for it
claude mcp list         # proxmox, github and terraform: Connected
```

## Limits

- **Never check the agent's branch out in your WSL clone to run it.**
  Review its pull request on GitHub and run its code with your credentials
  only after it's merged. A branch you check out runs its `mise.toml`
  tasks and pre-commit hooks with your credentials.
- **One user path:** `.claude/settings.json` points `SOPS_AGE_KEY_FILE` at
  `/home/bcochofel/.config/sops/age/ai-agent.txt`, and the container
  mounts the key at that same path. A different home directory means
  changing both.
