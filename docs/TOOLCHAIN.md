# Toolchain

Every tool this repo uses, why it's here, and where its version is
pinned. One rule runs
through all of it: **the same pinned versions everywhere** — on your
workstation, in CI and in the devcontainer — so a check that passes on
one passes on the others, and nothing changes version unless someone
decides it should.

## mise: one file for every tool

[mise](https://mise.jdx.dev) installs and activates every command-line
tool from `mise.toml`, at the exact versions pinned there.

### Installing mise

mise itself can't be pinned in `mise.toml`. Install it with mise's
official installer, which puts a single binary at `~/.local/bin/mise`:

```bash
curl -fsSL https://mise.run \
  | MISE_VERSION="$(sed -n 's/.*MISE_VERSION=\([^ ]*\).*/\1/p' .devcontainer/post-create.sh)" sh
~/.local/bin/mise --version
```

The version is pinned once, as `MISE_VERSION` in
`.devcontainer/post-create.sh`, and the command reads it from there (run
it from the repo root), so your workstation and the devcontainer run the
same mise.

`MISE_VERSION` goes on the `sh` side of the pipe, since `sh` runs the
installer. Without it, you get the latest release. To move to a newer
mise, bump `MISE_VERSION` in `post-create.sh` and in the command above
together, then re-run the installer (or `mise self-update <version>`).

Then activate it in your shell, so that entering the repo puts the
pinned tools first on your `PATH`, activates `.venv/` and sets the
non-secret `[env]` from `mise.toml`. Add the line for your shell and
start a new shell:

```bash
# bash
echo 'eval "$(~/.local/bin/mise activate bash)"' >> ~/.bashrc

# zsh
echo 'eval "$(~/.local/bin/mise activate zsh)"' >> ~/.zshrc
```

`~/.local/bin` doesn't have to be on your `PATH` beforehand; activation
takes care of it. This line is the only thing the repo needs in your
shell profile: it exports no secrets (see [`CREDENTIALS.md`](CREDENTIALS.md)).
Without activation, `mise run` and `mise exec` still work, but plain
commands like `tofu` or `ansible-playbook` don't get the pinned versions.
`mise doctor` shows whether activation is working.

### Installing the tools

```bash
mise trust && mise install   # every tool, .venv/, Ansible collections, git hooks
mise run doctor              # check the result
```

### Why mise

Why mise rather than a Makefile, system packages or one installer per
tool:

- **One declaration.** `mise.toml` lists every tool and version;
  `mise.lock` records each download's URL and checksum. Nothing is
  "whatever version your distro ships".
- **Verified installs.** CI (`jdx/mise-action` with `MISE_LOCKED=1`) and
  the devcontainer (`post-create.sh`) install in **locked mode**: exactly
  what `mise.lock` records, or fail. A version changed in `mise.toml`
  without `mise lock` fails CI.
- **Activation per directory.** Inside the repo, the pinned versions are
  first on your `PATH` and `.venv/` is active; outside it, your system
  tools are untouched.
- **Tasks.** The repo's commands are `mise run <task>`, defined next to
  the tool pins (`mise tasks` lists them): setup and checks, and the
  credentialed commands that decrypt one secret file for one command
  ([`CREDENTIALS.md`](CREDENTIALS.md)).

`mise install` ends by running `mise run bootstrap` (the `postinstall`
hook): git hooks, TFLint plugins, and Ansible plus its collections in
`.venv/`. Linux only: Ubuntu, native or under WSL2.

## The tools

The versions live in `mise.toml` (and the files under
[Pinned outside `mise.toml`](#pinned-outside-misetoml)), never in this
doc: `mise ls --current` shows what's installed.

### Pipeline: Packer → OpenTofu → Ansible

| Tool | Why |
| --- | --- |
| [Packer](https://developer.hashicorp.com/packer) | Builds the Ubuntu 26.04 VM template both VMs clone from ([`PACKER.md`](PACKER.md)). |
| [OpenTofu](https://opentofu.org) (`tofu`) | Clones the template into the VMs and writes the Ansible inventory ([`TERRAFORM.md`](TERRAFORM.md)). The open-source fork, against the same HCP Terraform state. |
| Terraform | Not used; pinned only as a rollback path from OpenTofu ([`TERRAFORM.md`](TERRAFORM.md)). |
| [Terramate](https://terramate.io) | Pinned for parity with `homelab-proxmox-workloads`, which uses it; nothing here uses it yet. |
| [Ansible](https://docs.ansible.com) | Configures the VMs ([`ANSIBLE.md`](ANSIBLE.md)). Lives in `.venv/`, not in `mise.toml` (see below). |

### Linting and docs

| Tool | Why |
| --- | --- |
| [TFLint](https://github.com/terraform-linters/tflint) | Catches provider-specific mistakes `tofu validate` doesn't (`.tflint.hcl`). |
| [terraform-docs](https://terraform-docs.io) | Keeps the inputs/outputs tables in `terraform/README.md` in step with the code. |
| [ShellCheck](https://www.shellcheck.net) | Lints every shell script: the Packer provisioners, `.devcontainer/post-create.sh`. They run as root on every build, so their bugs are expensive. |
| [ansible-lint](https://ansible.readthedocs.io/projects/lint/) | Lints roles and playbooks with the same `ansible-core` and collections they run with. |
| [markdownlint-cli2](https://github.com/DavidAnson/markdownlint-cli2) | Consistent Markdown across the docs (`.markdownlint.yaml`). |

### Security and policy

| Tool | Why |
| --- | --- |
| [Trivy](https://trivy.dev) | Misconfiguration scan of the OpenTofu code (`.trivy.yaml`, `.trivyignore`, this repo's own checks in `policies/trivy`). Runs on the repo, never inside the VMs. |
| [Checkov](https://www.checkov.io) | Policy-as-code checks on the OpenTofu code, including this repo's own policies (`policies/checkov`, `checkov.yaml`). Installed with pipx through mise. |
| [Gitleaks](https://gitleaks.io) | Blocks committing a secret: staged changes on every commit, the full history in CI (`mise run secrets`, `.gitleaks.toml`). |

### Secrets

| Tool | Why |
| --- | --- |
| [SOPS](https://getsops.io) | Encrypts the secret files (`~/.secrets/*.yaml`, `group_vars/*.sops.yaml`) and passes one file to one command (`sops exec-env`), so credentials never live in your shell. |
| [age](https://age-encryption.org) | The keys SOPS encrypts to: yours and the AI agent's, separately ([`CREDENTIALS.md`](CREDENTIALS.md)). Simpler than GPG, one file per key. |

### Git workflow and releases

| Tool | Why |
| --- | --- |
| [pre-commit](https://pre-commit.com) | Runs every check above on each commit, and all of them in CI (`mise run check`). Installed with pipx through mise. |
| [commitlint](https://commitlint.js.org) | Enforces Conventional Commits on commit messages (`commitlint.config.js`). |
| [semantic-release](https://semantic-release.gitbook.io) | Cuts versions, tags and release notes on `main` from those messages (`.releaserc.js`). Runs in CI only. |
| [GitHub CLI](https://cli.github.com) (`gh`) | Pull requests and run logs from the terminal. In the devcontainer it runs as the AI agent's machine user, through `.devcontainer/bin/gh` ([`DEVCONTAINER.md`](DEVCONTAINER.md)). |

### Runtimes

| Tool | Why |
| --- | --- |
| Python | For `.venv/` (Ansible, ansible-lint). |
| [uv](https://docs.astral.sh/uv/) | Installs `requirements.txt` into `.venv/`, much faster than pip. |
| Node.js | For the Node-based pre-commit hooks (commitlint, markdownlint-cli2) and semantic-release, so they don't depend on whatever Node is installed. |

### AI agent tooling

| Tool | Why |
| --- | --- |
| [github-mcp-server](https://github.com/github/github-mcp-server) | Read-only GitHub access for the AI agent ([`CREDENTIALS.md`](CREDENTIALS.md) step 8). |
| [terraform-mcp-server](https://github.com/hashicorp/terraform-mcp-server) | Public registry docs for the AI agent, so provider code isn't written from memory. Downloaded from `releases.hashicorp.com` with HashiCorp's checksum (HashiCorp publishes no GitHub release assets for it). |
| [mcp-proxmox](https://github.com/gilby125/mcp-proxmox) | Read-only Proxmox access for the AI agent. Not published as a package, so `mise run mcp:install` installs a reviewed commit. |
| Claude Code | The AI agent itself, installed in the devcontainer ([`DEVCONTAINER.md`](DEVCONTAINER.md)). |

## Pinned outside `mise.toml`

Some tools belong to an ecosystem with its own dependency file. Each is
pinned there:

| What | Where | How tightly |
| --- | --- | --- |
| Ansible, ansible-lint | `requirements.txt` → `.venv/` | Version ranges within one major release. Kept out of `mise.toml` so ansible-lint sees the same `ansible-core` and collections the playbooks run with. |
| Ansible collections (`community.docker`, `ansible.utils`, `community.sops`) | `ansible/requirements.yml` | Minimum versions. |
| pre-commit hooks | `.pre-commit-config.yaml` | Exact tags (`rev:`) for hook repos; the local hooks use the mise-pinned binaries. |
| semantic-release and plugins | `package.json` + `package-lock.json` | Exact, from the lockfile (`npm ci`). |
| OpenTofu providers (`bpg/proxmox`, `hashicorp/local`) | `.terraform.lock.hcl` (root and `modules/vm/`) | Exact versions and checksums. |
| Packer's Proxmox plugin | `packer/ubuntu-26.04/versions.pkr.hcl` | Minimum version. |
| Elastic Agent in the VM template | `elastic_agent_version` (Packer variable) | Exact, for the version a new clone starts at; Fleet upgrades it after enrollment. |
| Devcontainer base image and features | `.devcontainer/devcontainer.json`, `devcontainer-lock.json` | Exact image tag; features locked by digest. |
| CI actions | `.github/workflows/*.yml` | Major version tags. |

## Bumping a version

Nothing updates automatically: there's no Dependabot and no Renovate.
Bumps are deliberate, reviewed changes:

```bash
mise run outdated   # newer versions of pinned tools, and of pre-commit hooks
```

1. Edit the pin in `mise.toml` (or the file from the table above).
2. For `mise.toml`: `mise lock`, then `MISE_LOCKED=1 mise install` to check
   it installs.
3. Read the tool's release notes for anything that affects this repo, and
   run `mise run lint`.
4. Commit the pin and its lockfiles together (`mise.toml`, `mise.lock`,
   `.mise/locks/`).

`terraform-mcp-server` is the exception: its `mise.toml` entry has the
version, download URL and checksum written out, so a bump updates all
three (the checksum is in HashiCorp's `SHA256SUMS` file for that release).

## Known gaps

The Ansible collections and Packer's Proxmox plugin are pinned to minimum
versions only, and `requirements.txt` to ranges, so a fresh install can
pick up a newer release than the last one tested. Tighten them to exact
versions if that ever causes a surprise.
