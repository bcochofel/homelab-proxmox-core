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

- `proxy` (`192.168.68.40`, `proxy.homelab.bcochofel.com`) runs Caddy in
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
- `dns` (`192.168.68.41` VM management IP) runs CoreDNS and Pihole as two
  Docker Compose services, each on its own Docker macvlan IP —
  `192.168.68.42` (CoreDNS, `ns1`) and `192.168.68.43` (Pihole, `ns2`) —
  replacing the two containers that used to run in QNAP Container Station.
  `ansible/inventory/group_vars/dns.yml`'s `dns_hosts` list is the single
  source of truth for the local zone, feeding both services.

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
  itself has no ACME support; Caddy doesn't need that workaround. The
  Caddyfile's global `acme_dns cloudflare {$CLOUDFLARE_API_TOKEN}` option
  makes DNS-01 the default for every site block — no per-site `tls {}`
  needed.
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
  (`192.168.68.40`), not at the backend it proxies to.** This applies
  uniformly, including `pve1` (Proxmox's own web UI) — resolving straight
  to the backend bypasses Caddy entirely (no reverse proxy, and for most of
  these no valid public cert either). Kept in sync
  by hand between `caddy_sites` (`group_vars/all.yml`) and `dns_hosts`
  (`group_vars/dns.yml`) — no automation ties the two together.
- **CoreDNS + Pihole run on one VM but two Docker macvlan IPs, not one.**
  Docker's macvlan driver gives each container its own real LAN IP and MAC
  on the shared bridge, so both independently answer on port 53 — genuine
  `ns1`/`ns2` redundancy (matching the original QNAP naming), not one
  chained behind the other. The trade-off: **Docker's macvlan driver
  cannot be reached from its own Docker host by design** (a well-documented
  upstream Docker limitation) — so `playbooks/99-healthcheck.yml`'s DNS
  checks use `delegate_to: localhost` (the Ansible control machine) rather
  than running on the `dns` VM itself, which is also the more meaningful
  test (same vantage point a real LAN client has).
- **`dns_hosts` (`inventory/group_vars/dns.yml`) is the single source of
  truth for the local zone**, rendered into both CoreDNS's `hosts.local`
  and Pihole's `FTLCONF_dns_hosts` env var — a fresh start, not an import
  of the old QNAP-hosted Pihole gravity/blocklist state. Both services get
  the same `dns_forward_resolvers` (currently `1.1.1.1`/`8.8.8.8`) so
  either one alone is a fully working resolver, not just a passthrough to
  the other.
- **New IPs for CoreDNS/Pihole (`.42`/`.43`), not a reuse of the QNAP
  containers' `.5`/`.6`.** Deliberate — lets both run side by side during
  migration. Cutover (pointing DHCP at the new IPs, then decommissioning
  the QNAP containers) is a manual step, see `README.md`.
- **CoreDNS's docker-compose has no `HEALTHCHECK`.** The official
  `coredns/coredns` image is built `FROM scratch` (binary + CA certs only,
  no shell/wget/curl) — a `CMD-SHELL` healthcheck has nothing to execute.
  Real verification is the Ansible-level port-53 check above, not a
  Docker-level one.
- **Pihole's env vars (`FTLCONF_webserver_api_password`,
  `FTLCONF_dns_upstreams`, `FTLCONF_dns_hosts` in
  `roles/pihole/templates/env.j2`) are confirmed against
  <https://docs.pi-hole.net/docker/> (2026-08-12)** — Pi-hole v6's FTL-v6
  config system, `;`-delimited (or `\n`) for both array-typed vars. The
  first real run also caught `pihole_version: "2025.09.0"`
  (`inventory/group_vars/dns.yml`) as a nonexistent tag — training-data
  guesses at exact Pihole release versions still need a live Docker Hub
  check, same as the standing rule below about not trusting
  Caddy/Cloudflare specifics from memory.
- **Pihole has no `custom.list` file — never reintroduce one.** A second
  real run confirmed (2026-08-13, by reading `pihole-FTL`'s own
  `src/config/env.c`) that Pi-hole v6/FTL v6 never reads
  `/etc/pihole/custom.list` for local DNS records — `dns.hosts` stays `[]`
  even with the file present and bind-mounted; that mechanism is
  dnsmasq-era (Pi-hole v5) only. Local records must be forced via
  `FTLCONF_dns_hosts`, a `;`/`\n`-delimited array of `"IP HOSTNAME"`
  strings — same rule as `FTLCONF_dns_upstreams`.
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
- **DNS is now managed by this repo** (the `dns` VM), but router/DHCP
  configuration is not — pointing clients at the new `.42`/`.43` servers,
  and decommissioning the QNAP containers, are manual steps (see
  `README.md`'s "Migration cutover" and "DNS" sections).

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
- Caddy/Cloudflare/Pihole specifics may post-date the training cutoff:
  fetch current docs before changing ACME/DNS-01 config or Pihole env vars.

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
   `dns` VM is deployed and DHCP points clients at it (see README's
   "Migration cutover"). The public `bcochofel.com` Cloudflare zone only
   needs the ACME DNS-01 TXT records Caddy manages itself — no public
   A/AAAA record is needed for these LAN-only hostnames.

## Open / deferred work

Tracked in [`TODO.md`](TODO.md), not duplicated here.
