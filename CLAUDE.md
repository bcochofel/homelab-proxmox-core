# CLAUDE.md

Project context for Claude Code sessions — **not for humans**: never link or
reference this file from `README.md`, `CONTRIBUTING.md`, `TODO-SRE-AI.md`,
or anything under `docs/`. A human contributor's path is root `README.md`
(Quickstart, end-to-end) -> `docs/*.md` -> `CONTRIBUTING.md`.
`TODO-SRE-AI.md` is the homelab-wide SRE AI-autonomy roadmap (this repo +
`homelab-proxmox-workloads`) and the only TODO file; it lists only work
still to be implemented, never history. The per-tool READMEs
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
  Docker Compose. Caddy fronts three sites today —
  `nas.homelab.bcochofel.com` (QNAP QTS admin UI),
  `www.homelab.bcochofel.com` (QNAP Web Station / Home Studio KB pages),
  and `pve1.homelab.bcochofel.com` (the Proxmox VE web UI itself) — see
  `ansible/inventory/group_vars/all.yml`'s `caddy_sites` for the live list.
  Sites for `homelab-proxmox-workloads` backends are added with
  `external: true` once that repo deploys them.
- The `dns` VM (`192.168.68.15` VM management IP, Proxmox name/hostname
  `server01` — the Ansible inventory group is still `dns`, hardcoded in
  `terraform/templates/inventory.ini.tftpl` independent of the VM's own
  name) runs CoreDNS and Pihole as two Docker Compose services. CoreDNS
  (`192.168.68.2`) is the **authoritative primary** for
  `homelab.bcochofel.com`, transferring the zone via AXFR to a **secondary**
  CoreDNS instance on the user's QNAP NAS (`192.168.68.3` — its own
  dedicated LAN IP via QNAP's own network mechanism, not Docker's macvlan
  driver; entirely unmanaged by this repo) for read redundancy. Pihole (`192.168.68.5`) is
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
- **`../homelab-proxmox-workloads`** — OpenTofu + Terramate; the Elastic
  observability stack and the K3s cluster (ArgoCD, Traefik, OTel Demo).

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
- **Only `hosts.ini` is generated.** `ansible/inventory/group_vars/` is
  hand-authored and must never be overwritten by Terraform.
- **Proxied sites live in `inventory/group_vars/all.yml`'s `caddy_sites`
  list**, not in Terraform and not hardcoded in the Caddyfile template —
  adding a site is a one-entry change (the `Caddyfile.j2` template loops
  over the list). Sites whose backend lives in `homelab-proxmox-workloads`
  get `external: true`, so `99-healthcheck.yml` skips them.
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
  (`192.168.68.3` — its own LAN IP via QNAP's network mechanism, not
  Docker's macvlan driver; `secondary` plugin there — entirely outside this
  repo's Ansible). Pihole (`192.168.68.5`, same macvlan network — the
  primary instance) conditionally forwards `homelab.bcochofel.com` to both
  CoreDNS instances (`FTLCONF_dns_revServers`) rather than holding its own
  copy. Both CoreDNS instances restrict queries to `192.168.68.0/22` via
  the `acl` plugin.
- **Docker's macvlan driver cannot be reached from its own Docker host by
  design** (an upstream Docker limitation) — so `99-healthcheck.yml`'s DNS
  checks use `delegate_to: localhost` (the Ansible control machine), which
  is also the meaningful test (same vantage point a LAN client has).
- **`99-healthcheck.yml`'s site-retry loop uses `until: _sites.status in
  [200, 301, 302, 401, 403]`**, never `until: _sites.status is defined` —
  `ansible.builtin.uri` always returns a `status` (even `-1` on connection
  failure), so the latter is true on the first attempt and never retries.
  A fresh VM needs those retries while ACME issuance completes.
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
  secondary `.3`, Pihole primary `.5`, `pi3-01` (Pihole secondary) `.6`.
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
- **Pihole primary/secondary: `pi3-01`, a Raspberry Pi 3, runs the second
  Pihole — not Terraform-managed, not a VM.** It's in
  `inventory/hosts_static.ini`, loaded alongside Terraform's `hosts.ini`
  (`ansible.cfg` lists both files explicitly, not the `inventory/`
  directory, since Ansible's directory-scan `INVENTORY_IGNORE_EXTS`
  includes `ini` and would silently skip `hosts.ini`). Static IP
  `192.168.68.6`, SSH user `bcochofel`, Raspberry Pi OS — `roles/common`
  accepts `Debian`/`Raspbian` alongside `Ubuntu`, and `install_docker.yml`
  (gated on `docker_preinstalled: false` in `group_vars/pi3.yml`)
  installs Docker CE since Packer never touches this host. Scope is
  **config parity only**: both instances share identical settings
  (`group_vars/pihole.yml`) via the `pihole` children group (`dns` +
  `pi3`); `05-dns.yml` runs `dns_network`+`coredns` on `hosts: dns` and
  `pihole` on `hosts: pihole`. gravity.db/blocklists are deliberately
  **not** replicated (no gravity-sync, no Teleporter) — both start from
  Pi-hole's shipped defaults and every other setting is identical. pi3-01
  uses `network_mode: host` (single-purpose, no CoreDNS sharing port 53);
  `roles/pihole` branches on `pihole_network_mode` (`dns.yml`: `macvlan`;
  `pi3.yml`: `host`). Zone-wide vars (`dns_zone`, `coredns_ip`,
  `coredns_secondary_ip`, `dns_forward_resolvers`) live in
  `group_vars/all.yml` because pi3-01 isn't in the `dns` group.
- **CoreDNS plugin reference: <https://coredns.io/plugins/>.** The QNAP
  side's `secondary` plugin never persists the transferred zone to disk,
  so every restart there re-triggers a full AXFR from the primary —
  outside this repo's control.
- **Packer builds `ubuntu-26.04`**, minimal (Docker only). No in-VM Trivy,
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
  up (no stacks/`terramate.tm.hcl` yet), Python 3.14, no direnv (secrets reach
  tools through the `docs/CREDENTIALS.md` wrappers; mise only sets
  non-secret env), collections installed to
  Ansible's default path. **No Dependabot and no Renovate** — bumps are
  manual via `mise run outdated` + `mise lock`. **mise tasks are
  non-mutating only** (`setup:*`, `lint`, `secrets`, `check`, `doctor`,
  `outdated`) — deliberately **no Packer or Terraform tasks at all** (not
  even `init`/`validate`/`plan`). `packer`, `tofu` and `ansible-playbook`
  are run directly, by hand, from their own directory.
- **IaC engine is OpenTofu (`tofu`), state in HCP Terraform.** The
  `cloud {}` block needs `hostname = "app.terraform.io"` (OpenTofu has no
  default). `.terraform.lock.hcl` (root and `modules/vm/`) lists
  `registry.opentofu.org/...` providers, with `bpg/proxmox` pinned at
  `0.111.1`. The pre-commit-terraform hooks select `tofu` via
  `--hook-config=--tf-path=tofu` in `.pre-commit-config.yaml` — **not** the
  `PCT_TFPATH` env var: a commit from a shell without `mise activate`
  (shims only, IDE git UI) never sees mise.toml's `[env]`, falls back to
  `terraform`, and rewrites both lock files to `registry.terraform.io`.
  `terraform` stays pinned in `mise.toml` only as a rollback path (see
  `docs/TERRAFORM.md`). `tofu init` warns that bpg's signing key on the
  OpenTofu registry has expired.
- **Router/DHCP configuration and the QNAP CoreDNS secondary are not
  managed by this repo** — pointing clients at the resolvers and
  maintaining the QNAP secondary are manual steps (see `README.md`'s "Test
  DNS and configure your network" and "DNS" sections). DHCP hands out the
  Pi-hole pair (`.5`/`.6`), never a mix of Pi-hole and CoreDNS: clients
  don't reliably prefer the first server, so a mix makes ad-blocking
  inconsistent.

## Execution environment & tooling decisions

Linux only — Ubuntu, whether that's WSL2 or a native Linux workstation, never
PowerShell. Claude Code must be launched from the repo root so `packer`,
`tofu`, `ansible-playbook` (via `.venv/`), and `sops` resolve correctly.

Pipeline order is fixed: **Packer → Terraform → Ansible**. Do not skip ahead.

## Credentials & secrets

The human procedure is `docs/CREDENTIALS.md`; this is the agent-facing
summary.

- **No direnv, no `.envrc`.** Nothing is exported into the shell
  automatically. Read-only credentials are loaded on request (`hl_ro`);
  write credentials reach exactly one command through the wrappers
  `packer_rw`, `tofu_rw` (shell functions in `~/.secrets/homelab.sh`,
  outside the repo) and are never exported. Ansible needs no wrapper: it
  decrypts its own secrets at task time.
- **Where a secret goes:** credentials for non-Ansible tools, or shared
  across repos, go in `~/.secrets/`; secrets only Ansible uses, for this
  repo only, go in the encrypted `group_vars/<group>.sops.yaml` of the one
  group that needs them (per-group, not `all.sops.yaml`, so no other host
  sees them).
- **Secret files:** `~/.secrets/homelab-ro.yaml` (Proxmox endpoint/node,
  `ai-agent` token, HCP read-only token — encrypted to the human key and the
  `ai-agent` age key), `~/.secrets/homelab.yaml` (Packer/console tokens, HCP
  read-write token, `cloudinit_password`, `password_hash` — human key
  only), `ansible/inventory/group_vars/caddy.sops.yaml`
  (`cloudflare_api_token`) and `.../pihole.sops.yaml`
  (`pihole_webpassword`) — both human key only. The human age key is
  `~/.config/sops/age/keys.txt`; the `ai-agent` key is
  `~/.config/sops/age/ai-agent.txt` and only ever decrypts the RO file.
- Never read, print, echo, `cat`, `head`, `grep`, or `sed` any secret file
  (any `*.sops.yaml`, anything under `~/.secrets/`), the age keys, or
  `~/.secrets/homelab.sh`'s output. Reference secrets by key name only.
  Never run `packer_rw` or `tofu_rw`, and never run `ansible-playbook`
  unprompted (it decrypts secrets) — the write path is the human's.
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

## Proxmox auth — one identity per role (Proxmox VE 8.x)

- **`packer@pve!packer`** — role `PackerBuild`, template builds only.
- **`bcochofel@pve!console`** — role `TofuApply`, `tofu apply` (clone/
  configure; `VM.Allocate` and `VM.Config.CDROM` are both needed even
  though it only clones).
- **`ai-agent@pve!ai-agent`** — role `AiAgentRO` (`VM.Audit`,
  `Datastore.Audit`, `Sys.Audit`, `Pool.Audit`, `SDN.Audit`), read-only
  `tofu plan` and investigation. **Never add `VM.Monitor` to it**: on PVE 8
  that privilege also allows guest-agent command execution. On PVE 9,
  `VM.GuestAgent.Audit` is the read-only replacement.
- All tokens use `--privsep 1` with an ACL on both the user and the token.
- **No MCP servers are configured.** Read-only MCP servers are planned in
  `TODO-SRE-AI.md` Phase A8 — don't add an MCP server or agent credential
  outside that plan.
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

Local, read-only/validating checks run
freely; anything that actually writes infrastructure requires a human click
every time. `.claude/settings.json` (committed, shared policy) holds only
`deny` (secrets — every decrypting/editing `sops` subcommand (`-d`,
`decrypt`, `exec-env`, `exec-file`, `edit`, `set`, `unset`, `rotate`),
reading `*.sops.yaml`, `~/.secrets/` or the age keys, the write wrappers
`packer_rw`/`tofu_rw` — and `terraform`/`tofu destroy`) and `ask`
(`packer build`, `terraform`/`tofu apply`, `ansible-playbook`, ad-hoc
`ansible`, `ansible-console` — all of which can change hosts, and the
Ansible ones decrypt `*.sops.yaml` at task time) — no
`allow` list, so nothing risky or infrastructure-changing is ever
auto-approved by a checked-in file. Session/local convenience allowlists
(read-only command variants a contributor has already approved
interactively) belong in `.claude/settings.local.json` instead, which is
gitignored and per-developer, never shared policy. Use the `update-config`
skill for future changes here.

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

Packer, OpenTofu and Ansible commands have no mise task — the human runs
them directly, through the credential wrappers:

```bash
cd packer/ubuntu-26.04 && packer_rw build .
cd terraform && hl_ro && tofu plan -lock=false   # read-only plan
cd terraform && tofu_rw apply
cd ansible && ansible-playbook playbooks/site.yml      # .venv active via mise
```

## Before first run

1. `mise trust && mise install`.
2. Credentials per `docs/CREDENTIALS.md` (Proxmox roles/users/tokens, HCP
   tokens, `~/.secrets/` files, shell helpers).
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

- Decide whether the public `bcochofel.com` zone should get real A/AAAA
  records for these fqdns, or stay LAN-only with DNS-01 used only for
  certs.
- Consider access logging / rate limiting on `nas`/`www`/`pve1` if any is
  ever exposed beyond the LAN (`pve1` especially).
