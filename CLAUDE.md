# CLAUDE.md

Project context for Claude Code sessions — **not for humans**: never link or
reference this file from `README.md`, `CONTRIBUTING.md`, `TODO.md`, or
anything under `docs/`. A human contributor's path is root `README.md`
(Quickstart, end-to-end) -> `docs/*.md` -> `CONTRIBUTING.md`, with `TODO.md`
as the standing phase-status tracker. The per-tool READMEs
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
  Docker Compose. Caddy fronts four sites today —
  `kibana.homelab.bcochofel.com` (proxies to the `homelab-proxmox-elastic`
  repo's Kibana VM, `192.168.68.33`), `nas.homelab.bcochofel.com` (QNAP QTS
  admin UI), `www.homelab.bcochofel.com` (QNAP Web Station / Home Studio KB
  pages), and `pve1.homelab.bcochofel.com` (the Proxmox VE web UI itself)
  — see `ansible/inventory/group_vars/all.yml`'s `caddy_sites` for the live
  list. `otel-demo.homelab.bcochofel.com` was removed (2026-08-12) — the
  OTel Demo is planned to move to `../homelab-proxmox-k3s`'s cluster
  (deployed there via ArgoCD, fronted by Traefik as its in-cluster ingress)
  instead of staying a directly-proxied VM.
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

This repo is one of three that make up the homelab's overall architecture:

- **`homelab-proxmox-core`** (this repo) — the Caddy reverse proxy and
  CoreDNS+Pihole DNS pair, i.e. edge routing and name resolution for
  everything else.
- **`../homelab-proxmox-elastic`** — the Elastic observability stack
  (Elasticsearch, Kibana, Fleet Server, APM Server), including its own
  Packer -> Terraform -> Ansible pipeline.
- **`../homelab-proxmox-k3s`** — a K3s cluster, deployed via ArgoCD
  (GitOps) with Traefik as in-cluster ingress. It will run the OTel Demo
  and feed its telemetry into the `homelab-proxmox-elastic` stack, making
  it part of the observability architecture rather than a standalone
  workload.

This repo is architecturally a scoped-down sibling of
`../homelab-proxmox-elastic`: same tool pins, same SOPS/direnv/HCP-Terraform
pattern, same Docker Compose service style, deliberately built to as few
VMs as the actual workload needs (currently two). `../homelab-proxmox-k3s`
diverges more — Kubernetes/GitOps rather than Packer+Terraform+Ansible+
Docker Compose — since the workload it hosts (a multi-service demo app
managed declaratively) fits that model better than a hand-built VM.

## Decisions that are deliberate (do not "fix" these)

- **Terraform Provider is `bpg/proxmox`.** Same choice as the elastic repo,
  over Telmate (which the previous version of this repo used — the whole
  Terraform layer was rewritten, not incrementally migrated, since state
  from the old provider isn't compatible anyway).
- **Terraform State: HCP Terraform**, workspace `core-caddy` — a fresh
  workspace, not a reuse of this repo's old `core-components` workspace
  (which held Telmate-provider state).
- **Caddy runs via Docker Compose**, built from a role-rendered `Dockerfile`
  (matches the elastic repo's "DRY compose" pattern: identical
  `docker-compose.yml`, edit the role template, never the rendered files on
  the host).
- **Caddy's ACME is native, not certbot.** The image is built at deploy time
  via `xcaddy build --with github.com/caddy-dns/cloudflare`
  (`ansible/roles/caddy/templates/Dockerfile.j2`), so Caddy requests and
  renews its own Let's Encrypt certs via Cloudflare DNS-01 — no certbot, no
  systemd timer, no deploy-hook. This deliberately diverges from the
  elastic repo's `kibana_tls` role, which needs certbot only because Kibana
  itself has no ACME support; Caddy doesn't need that workaround.
- **DNS-01 is configured per-site via an explicit `tls { issuer acme {
  dns cloudflare ... \n resolvers ... } } }` block** (changed 2026-08-15,
  real failure hit after CoreDNS became authoritative for
  `homelab.bcochofel.com`). `resolvers` matters: the `proxy` VM's own
  system resolver is CoreDNS, which is authoritative for
  `homelab.bcochofel.com` — without `resolvers` pinned to public DNS
  (`letsencrypt_dns_resolvers` in `group_vars/all.yml`, currently
  `1.1.1.1`/`8.8.8.8`), Caddy's ACME zone-cut discovery gets a real SOA
  answer for `homelab.bcochofel.com` from our own CoreDNS and stops there,
  never walking up to the actual Cloudflare-hosted zone (`bcochofel.com`),
  failing with `"expected 1 zone, got 0 for homelab.bcochofel.com"`. This
  is a genuine side effect of the CoreDNS primary/secondary redesign, not
  a token or rate-limit issue — confirmed by directly querying the
  Cloudflare API with the token (it correctly sees `bcochofel.com`) and by
  matching this exact failure mode to `caddy-dns/cloudflare`'s documented
  behavior. **The `issuer acme { }` wrapper is required** — `resolvers` as
  a sibling of `dns` inside the global `acme_dns` one-liner, or inside the
  per-site `tls { dns cloudflare ... }` shorthand, is silently accepted by
  the Caddyfile parser but never reaches the running config (confirmed via
  Caddy's admin API config dump showing no `resolvers` key at all under
  `challenges.dns`) — a real, still-open upstream limitation
  (`caddyserver/caddy` issues #4008 and #7192), not a config mistake.
  Using an explicit `issuer acme { }` also drops Caddy's default ZeroSSL
  fallback issuer, which was never part of this repo's design and was
  generating unrelated timeout noise against ZeroSSL's API in the logs.
- **One Cloudflare API token, scoped to `bcochofel.com`, Zone:DNS:Edit +
  Zone:Zone:Read** — a *separate* token from the one the elastic repo's
  `kibana_tls` role uses, even though it's the same zone. Least-privilege
  boundary: this repo's token should not be reusable to touch the elastic
  repo's DNS records or vice versa.
- **Only `hosts.ini` is generated.** `ansible/inventory/group_vars/` is
  hand-authored and must never be overwritten by Terraform — same rule as
  the elastic repo.
- **Proxied sites live in `inventory/group_vars/all.yml`'s `caddy_sites`
  list**, not in Terraform and not hardcoded in the Caddyfile template —
  adding a new site is a one-entry change there, no role edit needed
  (the `Caddyfile.j2` template loops over the list).
- **Every Caddy-managed fqdn's DNS entry points at Caddy's IP
  (`192.168.68.16`), not at the backend it proxies to.** This applies
  uniformly, including `pve1` (Proxmox's own web UI) — resolving straight
  to the backend bypasses Caddy entirely (no reverse proxy, and for most of
  these no valid public cert either). Kept in sync
  by hand between `caddy_sites` (`group_vars/all.yml`) and `dns_hosts`
  (`group_vars/dns.yml`) — no automation ties the two together.
- **CoreDNS is primary/authoritative, not one of two independent peers.**
  (Redesigned 2026-08-15 — previously CoreDNS and Pihole were independent
  `ns1`/`ns2` peers, each with its own full copy of `dns_hosts`.) CoreDNS
  (`192.168.68.2`, on the `dns`/`server01` VM's Docker macvlan network)
  serves `homelab.bcochofel.com` authoritatively from a zone file (`file`
  plugin) and transfers it via AXFR (`transfer` plugin) to a secondary
  CoreDNS instance on the user's QNAP NAS (`192.168.68.3` — its own
  dedicated LAN IP via QNAP's own network mechanism, not Docker's macvlan
  driver; `secondary` plugin there — entirely outside this repo's Ansible). Pihole
  (`192.168.68.5`, same macvlan network — the **primary** instance, see the
  pi3-01 bullet below for its secondary) is ad-blocking only and
  conditionally forwards `homelab.bcochofel.com` to both CoreDNS instances
  (`FTLCONF_dns_revServers`) rather than holding its own copy. Both CoreDNS
  instances restrict queries to `192.168.68.0/22` via the `acl` plugin. The
  Docker macvlan host-isolation trade-off from the original design still
  applies: **Docker's macvlan driver cannot be reached from its own Docker
  host by design** (a well-documented upstream Docker limitation) — so
  `playbooks/99-healthcheck.yml`'s DNS checks use `delegate_to: localhost`
  (the Ansible control machine) rather than running on the VM itself, which
  is also the more meaningful test (same vantage point a real LAN client
  has).
- **`99-healthcheck.yml`'s "Wait for each proxied site to respond" retry
  loop was silently broken until 2026-08-15 — `until: _sites.status is
  defined` is true on the very first attempt regardless of success or
  failure**, since `ansible.builtin.uri` always returns a `status` field
  (even `-1` on total connection failure) — so `retries: 20` never
  actually retried anything. This went unnoticed for a long time because
  Caddy's certs were usually already cached from a prior deploy, so the
  first attempt normally just succeeded for real; it only surfaced once a
  genuinely fresh VM needed real time for ACME issuance and failed before
  getting it. Fixed to `until: _sites.status in [200, 301, 302, 401,
  403]` — the actual list `status_code:` already checks for.
- **The `caddy` role's `docker compose up -d --build` never picks up
  Caddyfile/`.env` *content* changes on its own — a real gap, fixed
  2026-08-15.** It runs unconditionally every play (see the task's own
  comment for why handlers were dropped: a stale-image-reference race in
  `community.docker.docker_compose_v2`'s idempotency check). That covers
  Dockerfile changes (image digest changes) and docker-compose.yml
  changes (service definition changes) — both of which `docker compose
  up` correctly detects and recreates for. It does **not** cover
  Caddyfile or `.env`: both are bind-mounted, not baked into the image,
  and `up` only diffs the service *definition*, never a bind-mounted
  file's *contents*. A content-only change to either was silently
  invisible forever — no error, the running Caddy process just kept its
  old in-memory config indefinitely. Fixed with an explicit `docker
  compose restart caddy` task, guarded on the Caddyfile/`.env` render
  tasks reporting `changed` (and skipped when `up` already recreated the
  container for an unrelated reason, to avoid a redundant restart).
- **`dns_hosts` (`inventory/group_vars/dns.yml`) is the single source of
  truth for the local zone**, rendered only into CoreDNS's zone file
  (`db.zone.j2`) now — Pihole no longer holds its own copy (see above).
  CoreDNS's catch-all `.` server block and Pihole's default upstream still
  share the same `dns_forward_resolvers` (currently `1.1.1.1`/`8.8.8.8`)
  for everything outside `homelab.bcochofel.com`.
- **CoreDNS/Pihole IPs: `.2`/`.3`/`.5`, reallocated from the earlier
  `.42`/`.43` scheme (2026-08-15).** Freed up by moving the `proxy` and
  `dns` VMs themselves off `.40`/`.41` to `.16`/`.15`. Notably, Pihole's new
  `.5` intentionally reuses the address the original QNAP-hosted CoreDNS/
  Pihole pair vacated during the Phase 1.5 migration (`.5`/`.6`, see
  `TODO.md`) — not an accidental collision. **Pre-flight caution, not
  verifiable from this repo:** confirm `.2`/`.3`/`.5`/`.15`/`.16` aren't
  already handed out by the router/DHCP pool before applying. Cutover
  (pointing DHCP at `.2`/`.5`) is a manual step, see `README.md`.
- **CoreDNS's docker-compose has no `HEALTHCHECK`.** The official
  `coredns/coredns` image is built `FROM scratch` (binary + CA certs only,
  no shell/wget/curl) — a `CMD-SHELL` healthcheck has nothing to execute.
  Real verification is the Ansible-level port-53 check above, not a
  Docker-level one.
- **Pihole's env vars (`FTLCONF_webserver_api_password`,
  `FTLCONF_dns_upstreams`, `FTLCONF_dns_revServers` in
  `roles/pihole/templates/env.j2`) are confirmed against
  <https://docs.pi-hole.net/docker/> (2026-08-12)** — Pi-hole v6's FTL-v6
  config system, `;`-delimited (or `\n`) for both array-typed vars. The
  first real run also caught `pihole_version: "2025.09.0"`
  (`inventory/group_vars/dns.yml`) as a nonexistent tag — training-data
  guesses at exact Pihole release versions still need a live Docker Hub
  check, same as the standing rule below about not trusting
  Caddy/Cloudflare specifics from memory. `FTLCONF_dns_revServers`'s format
  (`<enabled>,<ip-cidr>,<server>[#<port>][,<domain>]`) confirmed against
  <https://docs.pi-hole.net/ftldns/configfile/> (2026-08-15).
- **Pihole has no `custom.list` file and no `FTLCONF_dns_hosts` any more —
  never reintroduce either.** A second real run confirmed (2026-08-13, by
  reading `pihole-FTL`'s own `src/config/env.c`) that Pi-hole v6/FTL v6
  never reads `/etc/pihole/custom.list` for local DNS records — that
  mechanism is dnsmasq-era (Pi-hole v5) only. `FTLCONF_dns_hosts` itself
  was removed 2026-08-15 as part of the primary/secondary CoreDNS redesign
  above — CoreDNS's zone file is now the sole source of truth for local
  records, and Pihole conditionally forwards to it instead
  (`FTLCONF_dns_revServers`). Known trade-off: Pihole no longer
  auto-answers PTR (reverse) lookups for `dns_hosts` entries, and CoreDNS's
  zone file has no reverse zone either — unaddressed until/unless one's
  added later.
- **Pihole primary/secondary redundancy (added 2026-08-15): `pi3-01`, a
  Raspberry Pi 3, runs a second Pihole instance — not Terraform-managed,
  not a VM.** Hand-added to Ansible via `inventory/hosts_static.ini` (a
  second file loaded alongside Terraform's `hosts.ini` — `ansible.cfg`
  lists both explicitly, deliberately not the whole `inventory/`
  directory, since Ansible's directory-scan default
  `INVENTORY_IGNORE_EXTS` includes `ini` and would silently skip
  Terraform's own file). Static IP `192.168.68.6`, SSH user `bcochofel`,
  same key as the other hosts, Raspberry Pi OS (Debian-based) — `roles/
  common/tasks/asserts.yml`'s distro check was relaxed to accept `Debian`/
  `Raspbian` alongside `Ubuntu` (no version floor for those), and a new
  `install_docker.yml` task (gated on `docker_preinstalled: false` in
  `group_vars/pi3.yml`) installs Docker CE itself first, since Packer never
  touched this host. This scope is **config parity only**: both instances
  share identical Ansible-managed settings (`group_vars/pihole.yml` —
  version, timezone, web password, revServers subnet) via the `pihole`
  children group (`dns` + `pi3`), so `05-dns.yml` now runs
  `dns_network`+`coredns` on `hosts: dns` but `pihole` on `hosts: pihole`
  (both instances). It deliberately does **not** replicate gravity.db/blocklists
  — no gravity-sync, no Teleporter. Considered and rejected: both instances
  start from Pi-hole's own shipped defaults and every other setting is
  already identical via Ansible, so a separate sync mechanism wasn't judged
  worth the added moving parts. pi3-01
  is single-purpose (no CoreDNS sharing the host), so its Pihole container
  uses `network_mode: host` instead of the macvlan approach server01 needs
  — `roles/pihole`'s compose template and `pihole_base_dir`/`pihole_ip`
  branch per-host on `pihole_network_mode` (`group_vars/dns.yml`:
  `macvlan`; `group_vars/pi3.yml`: `host`). `dns_zone`/`coredns_ip`/
  `coredns_secondary_ip`/`dns_forward_resolvers` moved from
  `group_vars/dns.yml` to `group_vars/all.yml` since pi3-01 (not a member
  of the `dns` group) needs them too and CoreDNS still does as well.
- **CoreDNS's `file`/`transfer`/`acl` plugin syntax confirmed against
  <https://coredns.io/plugins/> (2026-08-15).** The `secondary` plugin
  (used on the QNAP-hosted secondary, outside this repo) has a real
  limitation worth remembering: it never persists the transferred zone to
  disk, so every container restart on the QNAP side re-triggers a full
  AXFR from the primary — not something this repo can fix, since that side
  is unmanaged by its Ansible.
- **Packer builds `ubuntu-26.04`**, minimal (Docker only) — adapted
  from the elastic repo's `packer/ubuntu-26.04/` template with the
  Elasticsearch-specific host tuning (`vm.max_map_count`, memlock/nofile
  limits, `/opt/elastic` base dir, pre-installed Elastic Agent) removed.
  This repo has no equivalent of the old `packer/ubuntu-24.04/` template
  (Alloy, system_report, custom-CA) — that tooling was dropped, not carried
  forward, since Caddy needs none of it. VMs do **not** self-scan with
  Trivy (unlike the elastic repo) — Trivy is still used at the repo level
  to scan this repo's own Terraform IaC (see `.trivy.yaml`/`.trivyignore`
  and `docs/TERRAFORM.md`), but there is no in-VM install or daily cron.
- **Terraform and Ansible are decoupled** — no `local-exec` chaining. Run
  `terraform apply` (from `terraform/`) then
  `ansible-playbook playbooks/site.yml` (from `ansible/`) as two separate,
  explicit commands.
- **The Makefile only has non-mutating targets** (`packer-init`, `tf-init`,
  `ansible-deps`, plus tool install/check). `packer build`, `terraform
  apply`, and `ansible-playbook` are deliberately NOT Makefile targets — run
  them directly, by hand, from their own directory.
- **DNS is now managed by this repo** (the `dns`/`server01` VM plus the
  QNAP-hosted CoreDNS secondary), but router/DHCP configuration is not —
  pointing clients at `.2`/`.5`, and standing up/maintaining the QNAP
  secondary, are manual steps (see `README.md`'s "DNS cutover" and "DNS"
  sections).

## Execution environment & tooling decisions

Linux only — Ubuntu, whether that's WSL2 or a native Linux workstation, never
PowerShell. Claude Code must be launched from the repo root so `packer`,
`terraform`, `ansible-playbook` (via `.venv/`), and `sops` resolve correctly.

Pipeline order is fixed: **Packer → Terraform → Ansible**. Do not skip ahead.

## Credentials & secrets

- Secrets live in `secrets.yaml`, SOPS-encrypted with **age**. `.sops.yaml` at
  repo root holds the recipient key — **a key generated specifically for
  this repo**, not shared with `homelab-proxmox-elastic`'s. The age private
  key is at `~/.config/sops/age/keys.txt` (chmod 600, never in the repo;
  the same file can hold multiple keys for multiple repos).
- **direnv** loads credentials per-directory. Root `.envrc` decrypts once
  (`sops -d --output-type dotenv secrets.yaml`) and child dirs inherit via
  `source_up`. `packer/`, `terraform/`, `ansible/` each add tool-specific vars.
- direnv runs in the human's shell *before* the agent starts. The Claude Code
  deny rule on `sops -d` restricts the agent, not direnv — both hold.
- Never read, print, echo, `cat`, `head`, `grep`, or `sed` any `.envrc`,
  `secrets.yaml`, or the age key. Reference secrets by variable name only.
- **`secrets.yaml` is meant to be committed** (it's ciphertext) —
  `.sops.yaml` and `.gitleaks.toml` both assume this. Never add
  `secrets.yaml`/`secrets.yml` to `.gitignore` — that was a real bug in a
  much earlier version of this repo (silently blocked the file from ever
  being committed) and stays fixed. Only decrypted output (`*.decrypted`,
  `*.dec.yaml`, `secrets.dec.yaml`) should ever be ignored.
- **Editing `secrets.yaml` needs no direnv action** — it reloads
  automatically on next `cd` (or `direnv reload`). **Editing any `.envrc`**
  makes direnv treat it as untrusted until re-approved — run
  `make direnv-allow` (re-approves all four: root, `packer/`, `terraform/`,
  `ansible/`).

## Proxmox auth — two tokens (+ optional third for MCP)

- **packer@pve!packer-automation** — template build rights.
- **terraform@pve!terraform-automation** — clone/configure rights + SSH to
  the PVE node for bpg file uploads. See `docs/TERRAFORM.md`'s privilege
  table for the exact `pveum` commands (same requirements as the elastic
  repo's Terraform token — `VM.Allocate` and `VM.Config.CDROM` are both
  needed even though Terraform only clones, never builds).
- **mcp@pve!mcp** (optional) — **read-only**, only if Proxmox MCP tooling is
  ever wired up here (see the elastic repo's CLAUDE.md "Agent-tooling
  rollout" for the pattern, not yet replicated in this repo).
- Env var shapes: Packer `PKR_VAR_*`; Terraform `PROXMOX_VE_*` /
  `TF_VAR_proxmox_api_token` (bpg/proxmox reads these directly).

## Terraform Cloud

Remote **state only**. Workspace Execution Mode = **Local**, because Proxmox
is LAN-only and HCP's infra can't reach it. `cloud {}` block
(`terraform/versions.tf`) points at org `homelab-bcochofel-com`, workspace
`core-caddy`. Always `plan` and show output; never `apply` unprompted; never
`destroy`.

## Command permissions (.claude/settings.json)

Same philosophy as the elastic repo: local, read-only/validating checks run
freely; anything that actually writes infrastructure requires a human click
every time. `.claude/settings.json` (committed, shared policy) holds only
`deny` (secrets — `sops -d`, `.envrc`, the age key — and `terraform destroy`)
and `ask` (`packer build`, `terraform apply`, `ansible-playbook`) — no
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
- Run `terraform validate` on every change — the provider schema will be
  hallucinated confidently otherwise.
- Caddy/Cloudflare/Pihole/CoreDNS specifics may post-date the training
  cutoff: fetch current docs before changing ACME/DNS-01 config, Pihole env
  vars, or CoreDNS plugin syntax.

## Commands

```bash
make install   # pinned CLI binaries, direnv approval, pre-commit hooks,
               # Ansible virtualenv + collections — everything a
               # contributor needs, one shot
```

Individual pieces, if you need to re-run just one — see `make help` for the
full list (`check`, `direnv-allow`, `pre-commit-install`, `venv`,
`ansible-install`, `ansible-deps`, `packer-init`, `tf-init`).

The write ops have no Makefile target — run them directly:

```bash
cd packer/ubuntu-26.04 && packer build .
cd terraform && terraform apply
cd ansible && ../.venv/bin/ansible-playbook playbooks/site.yml
```

## Before first run

1. `make install`.
2. Set in tfvars / HCP / env: `target_node` (`pve1`), `vm_template`
   (Packer template name), `TF_VAR_proxmox_api_token`, `TF_VAR_cipassword`.
3. Set in `secrets.yaml`, exported from `ansible/.envrc`:
   `CLOUDFLARE_API_TOKEN` (Caddy's ACME preflight) and
   `PIHOLE_WEBPASSWORD` (Pihole's preflight) — both required for
   `roles/common/tasks/asserts.yml` to pass. `letsencrypt_email` is not a
   secret — it's a plain value in `inventory/group_vars/all.yml`.
4. `dns_hosts` in `inventory/group_vars/dns.yml` already resolves every
   `caddy_sites` fqdn to Caddy's IP — no manual DNS step needed once the
   `dns`/`server01` VM is deployed and DHCP points clients at CoreDNS/
   Pihole (see README's "DNS cutover"). Standing up the QNAP-hosted CoreDNS
   secondary is a separate manual step, also covered there. The public
   `bcochofel.com` Cloudflare zone only needs the ACME DNS-01 TXT records
   Caddy manages itself — no public A/AAAA record is needed for these
   LAN-only hostnames.

## Open / deferred work

Tracked in [`TODO.md`](TODO.md), not duplicated here.
