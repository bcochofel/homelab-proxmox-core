# CLAUDE.md

Project context for Claude Code sessions — **not for humans**: never link or
reference this file from `README.md`, `CONTRIBUTING.md`, `TODO-SRE-AI.md`,
or anything under `docs/`. A human contributor's path is root `README.md`
(Quickstart, end-to-end) -> `docs/*.md` -> `CONTRIBUTING.md`.
`TODO-SRE-AI.md` is the homelab-wide SRE AI-autonomy roadmap (this repo +
`homelab-proxmox-workloads`) and the only TODO file. Implemented items
stay in it, ticked (`- [x]`), as a record — no dates, no incident notes;
tick an item only once its checks (`docs/CREDENTIALS.md` step 7,
`docs/DEVCONTAINER.md`) have passed. In those human-facing docs,
say "the AI agent", not "Claude Code", except where the text is about
the product itself (installing it, its hooks, skills or `.claude/` files).
The per-tool READMEs
(`packer/README.md`, `terraform/README.md`, `ansible/README.md`) are
deliberately just one-line pointers to their `docs/<TOOL>.md`.
`packer/ubuntu-26.04/README.md` is the exception that holds real content —
build steps and ADRs — since `packer/` is designed to hold multiple OS
templates over time and its own README stays generic.

## What this is

Two VMs on Proxmox — a Caddy reverse proxy and a CoreDNS+Pihole DNS
pair — built with the Packer -> Terraform -> Ansible pipeline:

```text
Packer (template) -> Terraform (clone VMs + generate inventory) -> Ansible (configure)
```

Topology:

- `proxy` (`192.168.68.16`, `proxy.homelab.bcochofel.com`) runs Caddy in
  Docker Compose. Caddy fronts five sites today —
  `nas.homelab.bcochofel.com` (QNAP QTS admin UI),
  `www.homelab.bcochofel.com` (QNAP Web Station / Home Studio KB pages),
  `pve1.homelab.bcochofel.com` (the Proxmox VE web UI itself) and
  `ha.homelab.bcochofel.com` (Home Assistant on the Raspberry Pi 3) and
  `kibana.homelab.bcochofel.com` (Kibana, from `homelab-proxmox-workloads`,
  over HTTPS verified against that repo's internal CA) — see
  `ansible/inventory/group_vars/all.yml`'s `caddy_sites` for the live list.
  Sites for other `homelab-proxmox-workloads` backends are added the same
  way.
- The `dns` VM (`192.168.68.15` VM management IP, Proxmox name/hostname
  `server01` — the Ansible inventory group is still `dns`, hardcoded in
  `terraform/templates/inventory.ini.tftpl` independent of the VM's own
  name) runs CoreDNS and Pihole as two Docker Compose services. CoreDNS
  (`192.168.68.2`) is the **authoritative primary** for
  `homelab.bcochofel.com`, transferring the zone via AXFR to a **secondary**
  CoreDNS instance on the user's QNAP NAS (`192.168.68.3` — its own
  dedicated LAN IP via QNAP's own network mechanism, not Docker's macvlan
  driver; entirely unmanaged by this repo) for read redundancy. Pihole
  (`192.168.68.5` primary on `server01`; `192.168.68.6` secondary in QNAP
  Container Station, also unmanaged by this repo) is
  **ad-blocking only** — it conditionally forwards `homelab.bcochofel.com`
  queries to both CoreDNS instances instead of holding its own copy of the
  records. Both CoreDNS instances only accept queries from
  `192.168.68.0/22`. `ansible/inventory/group_vars/dns.yml`'s `dns_hosts`
  list is the single source of truth for the local zone, feeding only
  CoreDNS's zone file now.

This repo is one of two that make up the homelab's overall architecture:

- **`homelab-proxmox-core`** (this repo) — the Caddy reverse proxy and
  CoreDNS+Pihole DNS pair, i.e. edge routing and name resolution for
  everything else.
- **`../homelab-proxmox-workloads`** — OpenTofu + Terramate; every
  workload behind the edge. What runs there isn't decided yet, so don't
  name specific services (Elastic, K3s, ...) when describing it.

Both repos share the same conventions: SOPS secrets, HCP state, mise
toolchain, Docker Compose service style.

## Decisions that are deliberate (do not "fix" these)

- **Terraform provider is `bpg/proxmox`** (not Telmate).
- **State: HCP Terraform**, workspace `core-caddy`.
- **Caddy runs via Docker Compose**, built from a role-rendered `Dockerfile`
  ("DRY compose": identical `docker-compose.yml`, edit the role template,
  never the rendered files on the host).
- **Caddy's ACME is native, not certbot.** The image is built at deploy time
  via `xcaddy build --with github.com/caddy-dns/cloudflare`
  (`ansible/roles/caddy/templates/Dockerfile.j2`), so Caddy requests and
  renews its own Let's Encrypt certs via Cloudflare DNS-01 — no certbot, no
  systemd timer, no deploy-hook.
- **DNS-01 is configured per-site via an explicit `tls { issuer acme {
  dns cloudflare ... \n resolvers ... } } }` block.** `resolvers` matters:
  the `proxy` VM's own system resolver is CoreDNS, which is authoritative
  for `homelab.bcochofel.com` — without `resolvers` pinned to public DNS
  (`letsencrypt_dns_resolvers` in `group_vars/all.yml`, `1.1.1.1`/
  `8.8.8.8`), Caddy's ACME zone-cut discovery gets a real SOA answer for
  `homelab.bcochofel.com` from our own CoreDNS and stops there, never
  walking up to the Cloudflare-hosted zone (`bcochofel.com`), failing with
  `"expected 1 zone, got 0 for homelab.bcochofel.com"`. **The `issuer acme
  { }` wrapper is required** — `resolvers` as a sibling of `dns` inside the
  global `acme_dns` one-liner, or inside the per-site `tls { dns cloudflare
  ... }` shorthand, is silently accepted by the Caddyfile parser but never
  reaches the running config (Caddy's admin API config dump shows no
  `resolvers` key under `challenges.dns`) — an open upstream limitation
  (`caddyserver/caddy` #4008, #7192). The explicit `issuer acme { }` also
  drops Caddy's default ZeroSSL fallback issuer; Let's Encrypt is the only
  issuer.
- **One Cloudflare API token, scoped to the `bcochofel.com` zone, with DNS
  Write and Zone Read** (dashboard group *DNS and Zones*), dedicated to this repo — never shared with
  `homelab-proxmox-workloads`, even though it's the same zone. Stored as
  `cloudflare_api_token` in `ansible/inventory/group_vars/caddy.sops.yaml`
  — only the `caddy` group needs it.
- **The `*.homelab.bcochofel.com` hostnames are LAN-only.** The public
  `bcochofel.com` zone gets no A/AAAA records for them; Cloudflare is
  used only for Caddy's ACME DNS-01 TXT records.
- **Only `hosts.ini` is generated.** `ansible/inventory/group_vars/` and
  `proxmox.ini` (the Proxmox nodes, reached as the `ansible` user) are
  hand-authored and must never be overwritten by Terraform.
- **Proxied sites live in `inventory/group_vars/all.yml`'s `caddy_sites`
  list**, not in Terraform and not hardcoded in the Caddyfile template —
  adding a site is a one-entry change (the `Caddyfile.j2` template loops
  over the list). Every backend is an external dependency for the
  healthcheck (below).
- **Every Caddy-managed fqdn's DNS entry points at Caddy's IP
  (`192.168.68.16`), not at the backend it proxies to** — including `pve1`.
  Resolving straight to the backend bypasses Caddy entirely (no reverse
  proxy, and for most backends no valid public cert). Kept in sync by hand
  between `caddy_sites` (`group_vars/all.yml`) and `dns_hosts`
  (`group_vars/dns.yml`) — no automation ties the two together.
- **CoreDNS is primary/authoritative; Pihole is ad-blocking only.** CoreDNS
  (`192.168.68.2`, on `server01`'s Docker macvlan network) serves
  `homelab.bcochofel.com` from a zone file (`file` plugin) and transfers it
  via AXFR (`transfer` plugin) to a secondary CoreDNS on the user's QNAP NAS
  (`192.168.68.3` — its own LAN IP via QNAP's `qnet` network driver, not
  Docker's macvlan driver; `secondary` plugin there — outside this repo's
  Ansible, applied by hand from `docs/EXTERNAL-DEPENDENCIES.md`). Pihole (`192.168.68.5`, same macvlan network — the
  primary instance) conditionally forwards `homelab.bcochofel.com` to both
  CoreDNS instances (`FTLCONF_dns_revServers`) rather than holding its own
  copy. Both CoreDNS instances restrict queries to `192.168.68.0/22` via
  the `acl` plugin.
- **Docker's macvlan driver cannot be reached from its own Docker host by
  design** (an upstream Docker limitation) — so `99-healthcheck.yml`'s DNS
  checks use `delegate_to: localhost` (the Ansible control machine), which
  is also the meaningful test (same vantage point a LAN client has).
- **`99-healthcheck.yml`: what this repo deploys fails the playbook;
  external dependencies never do.** Containers, port 53 on `.2`/`.5`, and
  Caddy serving a valid cert are hard failures. Backends behind
  `caddy_sites` and the QNAP secondaries are reported (`ignore_errors`,
  shown as failed), collected into `_external_issues`, and summarized by
  the last play. The site loop retries `until: _sites.status != -1` (no
  valid TLS answer yet, while ACME issues on a fresh VM) with
  `follow_redirects: none`, so it judges Caddy, not a backend's redirect
  target; never `until: _sites.status is defined` — `uri` always returns a
  `status` (`-1` on failure), so that never retries.
- **The `caddy` role restarts Caddy explicitly on Caddyfile/`.env` content
  changes.** `docker compose up -d --build` runs unconditionally every play
  (handlers race `community.docker.docker_compose_v2`'s idempotency check
  against stale image references — see the task comment). `up` recreates
  on Dockerfile or compose-definition changes, but Caddyfile and `.env` are
  bind-mounted, and `up` never diffs a bind-mounted file's contents — so a
  separate `docker compose restart caddy` task runs when either render task
  reports `changed` (skipped when `up` already recreated the container).
- **`dns_hosts` (`inventory/group_vars/dns.yml`) is the single source of
  truth for the local zone**, rendered only into CoreDNS's zone file
  (`db.zone.j2`). CoreDNS's catch-all `.` block and Pihole's default
  upstream share `dns_forward_resolvers` (`1.1.1.1`/`8.8.8.8`) for
  everything outside `homelab.bcochofel.com`.
- **IP plan:** `proxy` `.16`, `server01` `.15`, CoreDNS `.2`, QNAP CoreDNS
  secondary `.3`, Pihole primary `.5`, QNAP Pihole secondary `.6`, the
  Packer build VMs `192.168.71.0/24` (static, build-time only, one per
  template, `ubuntu-26.04` at `.71.1`; template README ADR-4), the
  dry-run runner `runner01` `.9` (`docs/RUNNER.md`, inventory group
  `github_runner`). The
  Raspberry Pi 3 runs Home Assistant at `.11` (not managed here),
  proxied by Caddy as `ha.homelab.bcochofel.com`. Everything this repo
  relies on but doesn't deploy (both QNAP secondaries, Home Assistant's
  proxy settings, the Vodafone Ultra Hub 7's Secure DNS setting) is
  documented in one place, `docs/EXTERNAL-DEPENDENCIES.md`.
  **Pre-flight caution, not verifiable from this repo:** confirm these
  aren't handed out by the router/DHCP pool before applying. Pointing DHCP
  at the resolvers is a manual step, see `README.md`.
- **CoreDNS's docker-compose has no `HEALTHCHECK`.** The official
  `coredns/coredns` image is built `FROM scratch` (no shell/wget/curl) — a
  `CMD-SHELL` healthcheck has nothing to execute. Verification is the
  Ansible-level port-53 check.
- **Pihole is configured through Pi-hole v6 FTL env vars**
  (`FTLCONF_webserver_api_password`, `FTLCONF_dns_upstreams`,
  `FTLCONF_dns_revServers` in `roles/pihole/templates/env.j2`), `;`-
  delimited (or `\n`) for array-typed vars — see
  <https://docs.pi-hole.net/docker/> and
  <https://docs.pi-hole.net/ftldns/configfile/>
  (`revServers`: `<enabled>,<ip-cidr>,<server>[#<port>][,<domain>]`).
  Check exact `pihole_version` tags on Docker Hub; don't guess them.
- **Never add a Pihole `custom.list` or `FTLCONF_dns_hosts`.** Pi-hole
  v6/FTL v6 never reads `/etc/pihole/custom.list` (a v5/dnsmasq-era
  mechanism), and local records belong only in CoreDNS's zone file.
  Accepted trade-off: Pihole doesn't auto-answer PTR lookups for
  `dns_hosts` entries, and CoreDNS has no reverse zone.
- **Pihole primary/secondary: the secondary runs in QNAP Container
  Station (`192.168.68.6`, `qnet` driver), set up by hand from
  `docs/EXTERNAL-DEPENDENCIES.md`, like the CoreDNS secondary.** Ansible
  deploys only the primary. The `pihole` group (`[pihole:children]` `dns`,
  in `terraform/templates/inventory.ini.tftpl`) keeps
  `group_vars/pihole.yml` as the single list of settings the secondary
  mirrors (`pihole_version`, `pihole_timezone`, `pihole_revserver_subnet`,
  plus zone-wide vars from `all.yml`); `roles/pihole/templates/env.j2`
  must only use those, never `dns.yml`. The secondary's web password is
  set with `pihole setpassword` on the NAS, not in its compose file.
  gravity.db/blocklists are deliberately **not** replicated (no
  gravity-sync, no Teleporter). `ansible.cfg` names `inventory/hosts.ini`
  and `inventory/proxmox.ini` explicitly, not the directory: Ansible's
  directory scan skips `.ini` files (`INVENTORY_IGNORE_EXTS`).
- **CoreDNS plugin reference: <https://coredns.io/plugins/>.** The QNAP
  side's `secondary` plugin never persists the transferred zone to disk,
  so every restart there re-triggers a full AXFR from the primary —
  outside this repo's control.
- **Packer builds `ubuntu-26.04`**, minimal: Docker, plus Elastic Agent
  (`scripts/30-install-elastic-agent.sh`, template README ADR-3): Elastic's
  signed Linux tarball (GPG + SHA-512 verified) at `elastic_agent_version`,
  installed with `elastic-agent install --non-interactive` (no `--url`) into
  `/opt/Elastic/Agent`, **not enrolled, service disabled and stopped** — a
  later Ansible playbook enrolls it (`elastic-agent enroll`) and enables it.
  Tarball, not DEB, so Fleet can upgrade it; `elastic_agent_version` only
  sets the version new clones start at. No in-VM Trivy,
  no Alloy/system_report/custom-CA tooling. Trivy is used at the repo
  level to scan this repo's IaC (`.trivy.yaml`/`.trivyignore`,
  `docs/TERRAFORM.md`).
- **Terraform and Ansible are decoupled** — no `local-exec` chaining. Run
  `tofu apply` (from `terraform/`) then `ansible-playbook
  playbooks/site.yml` (from `ansible/`) as two separate, explicit commands.
- **Toolchain is `mise.toml`, not a Makefile** (modelled on
  `~/Projects/GitHub/sre-repo-template`). It pins every CLI tool (checksums
  in `mise.lock` + `.mise/locks/`, CI installs with `MISE_LOCKED=1` via
  `jdx/mise-action`), activates `.venv/`, and its `postinstall` hook runs
  `mise run bootstrap`. Deliberate differences from the template: no
  Azure/`plan` task (Proxmox is LAN-only), Terramate pinned but not wired
  up (no stacks/`terramate.tm.hcl` yet), Python from `mise.toml`, no direnv (secrets reach
  each command through `sops exec-env` inside a mise task; mise's `[env]`
  only sets non-secret env), collections installed to
  Ansible's default path. **No Dependabot and no Renovate** — bumps are
  manual via `mise run outdated` + `mise lock`. `docs/TOOLCHAIN.md`
  explains each tool and where it's pinned; it deliberately holds no version
  numbers (they'd go stale), so update it only when a tool is added or removed
  — except mise's own install command, whose `MISE_VERSION` must match
  `.devcontainer/post-create.sh`'s (bump both together). **mise tasks:**
  setup and checks (`setup:*`, `lint`, `secrets`, `check`, `doctor`,
  `outdated`), plus the credentialed commands at the bottom of
  `mise.toml`: `packer:build`, `tofu:init`, `tofu:plan`, `tofu:apply`.
  Each wraps one command in `sops exec-env ~/.secrets/homelab.yaml` and is
  the human's: the agent's key can't decrypt that file, and the ones that
  change anything are also denied. **The agent has no state access:** HCP
  Terraform Free has no teams, so it can't issue a read-only state token
  (`TODO-SRE-AI.md` A1 tracks adding one). The agent's OpenTofu checks are
  `tofu init -backend=false` + `tofu validate` (+ `mise run lint`).
  `ansible:site` (the playbook, with the human key as
  `ANSIBLE_SOPS_AGE_KEYFILE`), `sops`, `secrets:check` and `creds:check`
  are human tasks too, all denied to the agent. `boundary:check` uses only
  the `ai-agent` key and prints no values; the agent may run it (WSL or
  devcontainer).
- **IaC engine is OpenTofu (`tofu`), state in HCP Terraform.** The
  `cloud {}` block needs `hostname = "app.terraform.io"` (OpenTofu has no
  default). `.terraform.lock.hcl` (root and `modules/vm/`) lists
  `registry.opentofu.org/...` providers, with `bpg/proxmox` pinned
  there. The pre-commit-terraform hooks select `tofu` via
  `--hook-config=--tf-path=tofu` in `.pre-commit-config.yaml` — **not** the
  `PCT_TFPATH` env var: a commit from a shell without `mise activate`
  (shims only, IDE git UI) never sees mise.toml's `[env]`, falls back to
  `terraform`, and rewrites both lock files to `registry.terraform.io`.
  `terraform` stays pinned in `mise.toml` only as a rollback path (see
  `docs/TERRAFORM.md`). `tofu init` warns that bpg's signing key on the
  OpenTofu registry has expired.
- **Router/DHCP configuration and the QNAP secondaries (CoreDNS and
  Pihole) are not managed by this repo** — pointing clients at the
  resolvers and maintaining the QNAP secondaries are manual steps (see
  `README.md`'s "Test DNS and configure your network" and "DNS" sections,
  `docs/EXTERNAL-DEPENDENCIES.md`). **Keep its CoreDNS and Pi-hole
  sections in step with the primaries:** the CoreDNS doc's Corefile `.:53`
  block mirrors `roles/coredns/templates/Corefile.j2`'s catch-all (ACL
  subnet, `dns_forward_resolvers`) and its image tag matches
  `coredns_version`; the Pihole doc's settings table, compose
  `environment` and image tag mirror `group_vars/pihole.yml`, the
  zone-wide vars in `all.yml`, and `roles/pihole/templates/env.j2` —
  update them whenever any of those change. DHCP hands out the
  Pi-hole pair (`.5`/`.6`), never a mix of Pi-hole and CoreDNS: clients
  don't reliably prefer the first server, so a mix makes ad-blocking
  inconsistent.

- **CI dry-runs run on a self-hosted runner, never on the agent**
  (`docs/RUNNER.md`, `TODO-SRE-AI.md` A10; being built in the order that
  doc lists, so check what exists before relying on any piece). `runner01`
  holds a plan-scoped `ci` identity: `ci@pve!plan` (`AiAgentRO`), an HCP
  token that can write state (accepted risk on Free), an automation SSH
  key, and a `ci` age key that opens `ci/dry-run.sops.yaml`,
  `ci/ssh_ed25519.sops` and the inventory files, never `~/.secrets/*`;
  the `ai-agent` key opens none of them. GitHub holds only `CI_AGE_KEY`,
  a `dry-run` environment secret. The boundary is that environment's
  required reviewer (the human): `dry-run.yml` is `pull_request` only
  (never `pull_request_target`), same-repo PRs only, `contents: read`.
  Public logs get only the plan summary and the Ansible recap; the full
  output is an age-encrypted artifact (human + `ai-agent`), `tfplan` is
  never uploaded. Runner self-update stays on. The agent never writes
  `.github/workflows/` (its token can't push them): it puts workflow
  files in the PR description for the human to commit. Decided:
  `runner01` `192.168.68.9`, owned by this repo. Open (ask, don't pick):
  how the runner gets `hosts.ini`/tfvars, which HCP token type `ci` uses.

## Execution environment & tooling decisions

Linux only — Ubuntu, whether that's WSL2 or a native Linux workstation, never
PowerShell. Claude Code must be launched from the repo root so `packer`,
`tofu`, `ansible-playbook` (via `.venv/`), and `sops` resolve correctly.

Pipeline order is fixed: **Packer → Terraform → Ansible**. Do not skip ahead.

## Credentials & secrets

The human procedure is `docs/CREDENTIALS.md`; this is the agent-facing
summary.

- **No direnv, no `.envrc`, nothing in `~/.zshrc`.** Nothing is ever
  exported into the shell. Credentialed commands are `mise run` tasks that
  pass one decrypted file to one command via `sops exec-env`. Ansible
  decrypts its own secrets at task time.
- **Two age keys; Claude Code has only the `ai-agent` one.**
  `.claude/settings.json` `env` sets `SOPS_AGE_KEY_FILE` and
  `ANSIBLE_SOPS_AGE_KEYFILE` to `~/.config/sops/age/ai-agent.txt` for every
  command the agent runs, so it can decrypt `homelab-ro.yaml` and
  `ai-agent-git.yaml` and nothing else (not `homelab.yaml`, not the
  inventory secrets). Soft boundary: the
  agent runs as the human's OS user and only deny rules keep it from the
  human key. The hard boundary is the devcontainer
  (`.devcontainer/`, `docs/DEVCONTAINER.md`): it mounts only the
  `ai-agent` key (at the same absolute path, so the `env` block still
  resolves), `homelab-ro.yaml` and `ai-agent-git.yaml`, never the human
  key, `homelab.yaml`, the Docker socket, the human's ssh-agent
  (`SSH_AUTH_SOCK=""`) or VS Code's git credential helper. **Two clones,
  never a shared working copy:** the agent's clone is a separate WSL
  folder, `~/Projects/ai-agent/homelab-proxmox-core`, opened only with
  *Reopen in Container* (the agent owns it, `.git` included; *Clone
  Repository in Container Volume* needs Docker Desktop, and Docker Engine
  runs inside WSL here); the human never runs anything from it and runs
  every credentialed task only from his own WSL clone,
  `~/Projects/GitHub/BCochofelHomelab/homelab-proxmox-core`, on merged
  code. `boundary:check` fails if the container's workspace is mounted
  from the human's clone. Bootstrap stays skipped in the container
  (pre-commit refuses `install` with `core.hooksPath` set).
  `boundary:check` on WSL flags `.git/config` keys that run code, since
  the agent's WSL sessions can write that file.
- **The agent's GitHub identity is the machine user `bcochofel-ai-agent`,
  in the devcontainer only** (`docs/GITHUB.md`, `docs/CREDENTIALS.md`
  step 9). `devcontainer.json`'s `GIT_CONFIG_*` set its commit identity,
  rewrite the SSH remote to HTTPS, clear every credential helper but
  `.devcontainer/bin/git-credential-ai-agent`, and point `core.hooksPath`
  at `.devcontainer/git-hooks`; `gh` there is the `.devcontainer/bin/gh`
  wrapper (added to PATH after `mise activate` in post-create, so it beats
  mise's `gh`). It gets Write through the `sre-team` team; `sre-lead`
  (the human only) owns every file in CODEOWNERS and each repo's
  `protected-default` ruleset requires a code-owner approval. Rulesets
  don't control who clicks merge, and tag creation isn't restricted (it
  would block semantic-release): only `.claude/settings.json` stops the
  agent merging an approved PR, approving, tagging or writing through
  `gh api`. Pushes go over HTTPS with the token, never SSH: the token's
  missing Workflows permission only blocks token pushes. PR descriptions
  carry no "Generated with Claude Code" line (`attribution.pr: ""`); the
  commit `Co-Authored-By` trailer stays. In the agent's clone,
  `post-create.sh` merges `allow` rules for `git push` and `gh pr create`
  into its gitignored `.claude/settings.local.json`: the PR is the
  checkpoint, GitHub enforces the limits. On WSL, git and `gh` are the
  human's: his clone's own `settings.local.json` holds `ask` rules for
  both (`docs/DEVCONTAINER.md`); push or open PRs there only when the
  human asks.
- **Where a secret goes:** credentials for non-Ansible tools, or shared
  across repos, go in `~/.secrets/`; secrets only Ansible uses, for this
  repo only, go in the encrypted `group_vars/<group>.sops.yaml` of the one
  group that needs them (per-group, not `all.sops.yaml`, so no other host
  sees them).
- **Secret files (keys are env var names):** `~/.secrets/homelab.yaml`
  (read-write: `PKR_VAR_*` incl. the Packer token and `password_hash`, the
  `terraform` `TF_VAR_proxmox_api_token`, `TF_VAR_cipassword`, the HCP
  read-write `TF_TOKEN_app_terraform_io` — human key only),
  `~/.secrets/homelab-ro.yaml` (read-only: the `PROXMOX_*` (the
  `ai-agent` Proxmox token) and `GITHUB_PERSONAL_ACCESS_TOKEN` MCP
  credentials, no OpenTofu/HCP keys — human + `ai-agent` keys), `ansible/inventory/group_vars/caddy.sops.yaml`
  (`cloudflare_api_token`) and `.../pihole.sops.yaml`
  (`pihole_webpassword`) — both human key only, never `ai-agent` (even
  `--check` decrypts them; the agent's Ansible remit is lint and
  syntax-check), `~/.secrets/ai-agent-git.yaml` (`GH_TOKEN`, the
  machine user's fine-grained PAT — human + `ai-agent` keys). Human key
  `~/.config/sops/age/bcochofel.txt` —
  deliberately **not** SOPS's default `keys.txt`: SOPS reads the default
  file in every process on top of `SOPS_AGE_KEY_FILE`, which would give the
  agent's commands the human key. Every human task passes it explicitly
  (task-level `env` in `mise.toml`). Never suggest moving it back.
  `ai-agent` key `~/.config/sops/age/ai-agent.txt`; the MCP servers get it
  via `claude mcp add -e SOPS_AGE_KEY_FILE=...`.
- Never read, print, echo, `cat`, `head`, `grep`, or `sed` any secret file
  (any `*.sops.yaml`, anything under `~/.secrets/`) or the age keys.
  Reference secrets by key name only. Never run `packer:build` or any
  `tofu:*` task, and never run `ansible-playbook` unprompted — the
  credentialed path is the human's.
- **`*.sops.yaml` files are meant to be committed** (they're ciphertext)
  — `.sops.yaml` and `.gitleaks.toml` both assume this. Never add them to
  `.gitignore`. Only decrypted output (`*.decrypted`, `*.dec.yaml`) should
  ever be ignored.
- **Ansible secrets: `community.sops` vars plugin, `vars_stage = task`**
  (`ansible/ansible.cfg`). Encrypted group vars (`group_vars/<group>.sops.yaml`)
  are decrypted only while a task runs, so `ansible-lint`,
  `--syntax-check` and `ansible-inventory` never decrypt — the agent's
  Ansible remit (lint, syntax-check, reading playbooks) needs no secrets.
  `vars_plugins_enabled` must keep `host_group_vars` first: the setting
  replaces Ansible's default list.
- **`password_hash` must not be in `variables.auto.pkrvars.hcl`** — a
  varfile value takes precedence over `PKR_VAR_password_hash`.

## Proxmox auth — one identity per role (Proxmox VE 9.x)

- **`packer@pve!packer`** — role `PackerBuild`, template builds only.
- **`terraform@pve!terraform`** — role `TofuApply`, `tofu apply` (clone/
  configure; `VM.Allocate` and `VM.Config.CDROM` are both needed even
  though it only clones).
- **`ai-agent@pve!ai-agent`** — role `AiAgentRO` (`VM.Audit`,
  `VM.GuestAgent.Audit`, `Datastore.Audit`, `Sys.Audit`, `Pool.Audit`,
  `SDN.Audit`), read-only `tofu plan` and investigation.
- PVE 9 dropped `VM.Monitor`; guest-agent access is `VM.GuestAgent.*`.
  Every role gets `VM.GuestAgent.Audit` (read-only: VM IPs) and **never**
  `VM.GuestAgent.Unrestricted` (runs programs in the VM), `FileRead`,
  `FileWrite` or `FileSystemMgmt`. The QEMU HMP monitor now needs
  `Sys.Audit`; nothing here uses it.
- All tokens use `--privsep 1` with an ACL on both the user and the token.
- **MCP servers: read-only, project scope (`.mcp.json`), `docs/CREDENTIALS.md`
  step 8.** One committed `.mcp.json` serves WSL and the devcontainer:
  Proxmox (`ai-agent@pve!ai-agent`, `PROXMOX_ALLOW_ELEVATED=false`;
  `gilby125/mcp-proxmox` at a commit pinned in the `mcp:install` task),
  GitHub (`github-mcp-server --read-only`, read-only fine-grained PAT) and
  Terraform (`terraform-mcp-server --toolsets=registry`, no `TFE_TOKEN`);
  the two binaries are pinned in `mise.toml` (terraform-mcp-server via the
  `http:` backend: HashiCorp publishes no GitHub release assets). The
  credentialed ones start through `sops exec-env ${HOME}/.secrets/homelab-ro.yaml`
  with `SOPS_AGE_KEY_FILE=${HOME}/.config/sops/age/ai-agent.txt`; no token
  is ever in `.mcp.json`. The devcontainer mounts the `ai-agent` key under
  `/home/vscode` too so `${HOME}` resolves there. MCP servers for the
  workloads belong to `homelab-proxmox-workloads`. Don't add a server, or
  give one a write credential, outside that step and `TODO-SRE-AI.md`
  Phase A8.
- Env var shapes: Packer `PKR_VAR_*`; OpenTofu `TF_VAR_proxmox_api_token`
  (`user@realm!tokenid=secret`), `TF_VAR_cipassword`,
  `TF_TOKEN_app_terraform_io`.

## Terraform Cloud

Remote **state only**. Workspace Execution Mode = **Local**, because Proxmox
is LAN-only and HCP's infra can't reach it. `cloud {}` block
(`terraform/versions.tf`) points at org `homelab-bcochofel-com`, workspace
`core-caddy`. Always `plan` and show output; never `apply` unprompted; never
`destroy`.

## Command permissions (.claude/settings.json)

Local, read-only/validating checks run freely; anything that writes
infrastructure or touches the human's key needs a human. The committed
`.claude/settings.json` holds these blocks and no `allow` list:

- `disableClaudeAiConnectors: true`: the user's claude.ai connectors
  (Drive, Gmail, Jira, ...) don't load in this repo. Several have write
  tools, outside the read-only model; only `.mcp.json`'s servers apply.

- `env`: `SOPS_AGE_KEY_FILE` and `ANSIBLE_SOPS_AGE_KEYFILE` → the
  `ai-agent` key.
- `deny`: reading the age keys (`bcochofel.txt`, `ai-agent.txt`, and
  `keys.txt` as a guard), `~/.secrets/` and `group_vars/*.sops.yaml` (the
  root `.sops.yaml` holds only public keys and stays readable); every
  decrypting/editing `sops` subcommand (`-d`, `--decrypt`, `decrypt`,
  `edit`, `exec-env`, `exec-file`, `set`, `unset`, `rotate`); every mise
  task that uses the human key (`packer:build`, `tofu:init|plan|apply`,
  `ansible:site`, `sops`, `secrets:edit`, `secrets:check`, `creds:check`);
  `terraform`/`tofu destroy`; running the credential helper or `git
  credential`; force/deleting pushes; `gh auth`, `gh pr merge`, `gh pr
  review`, `gh release`, `gh repo delete`, `gh secret`, `gh variable`,
  `gh workflow`, every `gh api` write form (`-X`, `--method`, `-f`, `-F`,
  `--field`, `--raw-field`, `--input`), `git tag` and tag pushes.
- `ask`: `packer build`, `terraform`/`tofu apply`, `ansible-playbook` and
  ad-hoc `ansible`/`ansible-console` (they can change hosts, and Ansible
  decrypts `*.sops.yaml` at task time). `git push` and `gh pr create`
  aren't in the shared file: each clone's `settings.local.json` sets them
  (`allow` in the agent's, `ask` in the human's).

A rule `Bash(cmd *)` also matches plain `cmd`, so each command needs only
the `*` form. Session/local convenience allowlists belong in the
gitignored `.claude/settings.local.json`, never in shared policy. Use the
`update-config` skill for future changes here.

## Standing rules

- **Never overwrite `inventory/group_vars/`.** Terraform generates
  `hosts.ini`; `inventory/group_vars/` is hand-authored.
- **DRY compose:** one `docker-compose.yml`, built by a role-rendered
  `Dockerfile`, never hand-edited on the host.
- Run `tofu validate` on every change — the provider schema will be
  hallucinated confidently otherwise.
- Caddy/Cloudflare/Pihole/CoreDNS specifics may post-date the training
  cutoff: fetch current docs before changing ACME/DNS-01 config, Pihole env
  vars, or CoreDNS plugin syntax.

## Commands

```bash
mise trust && mise install   # pinned tools, .venv + Ansible collections,
                             # pre-commit hooks — everything a contributor
                             # needs, one shot (credentials: docs/CREDENTIALS.md)
```

Individual pieces, if you need to re-run just one — see `mise tasks` for
the full list (`bootstrap`, `setup:hooks`, `setup:tflint`,
`setup:ansible`, `lint`, `secrets`, `check`, `doctor`, `outdated`).

Credentialed commands (human only):

```bash
mise run packer:build
mise run tofu:init
mise run tofu:plan      # as terraform — the one to review; saves terraform/tfplan
mise run tofu:apply     # applies terraform/tfplan (no prompt)
mise run ansible:site   # ansible-playbook playbooks/site.yml with the human key
mise run sops -- <args> # sops with the human key (edit, updatekeys)
mise run secrets:edit -- homelab-ro.yaml  # sops on a ~/.secrets file, from ~/.secrets
mise run secrets:check  # every ~/.secrets file opens with the right key only
mise run creds:check    # every credential authenticates (read-only API calls)
mise run boundary:check # the agent's boundary holds (agent may run this one)
```

## Before first run

1. `mise trust && mise install`.
2. Credentials per `docs/CREDENTIALS.md` (Proxmox roles/users/tokens, HCP
   tokens, the two `~/.secrets/` files).
3. Set in `terraform.tfvars`: `target_node` (the Proxmox node name), `vm_template`
   (Packer template name), `sshkeys`.
4. `ansible/inventory/group_vars/caddy.sops.yaml` holds
   `cloudflare_api_token` (Caddy's ACME preflight) and `pihole.sops.yaml`
   holds `pihole_webpassword` (Pihole's preflight) — both required for
   `roles/common/tasks/asserts.yml` to pass. `letsencrypt_email` is not a
   secret — it's a plain value in `inventory/group_vars/all.yml`.
5. `dns_hosts` in `inventory/group_vars/dns.yml` already resolves every
   `caddy_sites` fqdn to Caddy's IP — no manual DNS step needed once the
   `dns`/`server01` VM is deployed and DHCP points clients at the Pi-hole
   pair (see README's "Test DNS and configure your network"). Standing
   up the QNAP-hosted CoreDNS secondary is a separate manual step. The public
   `bcochofel.com` Cloudflare zone only needs the ACME DNS-01 TXT records
   Caddy manages itself — no public A/AAAA record is needed for these
   LAN-only hostnames.

## Open / deferred work

SRE AI-autonomy work is tracked in `TODO-SRE-AI.md`. Other open decisions:

- Consider access logging / rate limiting on `nas`/`www`/`pve1`/`ha` if any is
  ever exposed beyond the LAN (`pve1` especially).
