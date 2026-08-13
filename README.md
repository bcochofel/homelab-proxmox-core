# homelab-proxmox-core

Two VMs on Proxmox (pve1), built with an IaC pipeline: `proxy` (Caddy
reverse proxy) and `dns` (CoreDNS + Pihole).

```text
Packer (template)  ->  Terraform (clone VMs + generate inventory)  ->  Ansible (configure)
```

## Homelab architecture

This repo is one of three that make up the homelab:

- **`homelab-proxmox-core`** (this repo) — edge routing and name
  resolution: the Caddy reverse proxy and the CoreDNS + Pihole DNS pair.
- **[`homelab-proxmox-elastic`](https://github.com/bcochofel/homelab-proxmox-elastic)**
  — the Elastic observability stack (Elasticsearch, Kibana, Fleet Server,
  APM Server), built with the same Packer -> Terraform -> Ansible pipeline
  as this repo.
- **[`homelab-proxmox-k3s`](https://github.com/bcochofel/homelab-proxmox-k3s)**
  — a K3s cluster managed via ArgoCD (GitOps), with Traefik as its
  in-cluster ingress.
  It runs the OTel Demo, which feeds telemetry into the
  `homelab-proxmox-elastic` stack — so the cluster is part of the
  observability architecture, not a standalone workload.

## Quickstart

Get both VMs green on Proxmox, end to end. See
[Design decisions](#design-decisions) below for topology and rationale, and
[`CONTRIBUTING.md`](CONTRIBUTING.md) if you're setting this up to
contribute rather than just to run it.

### Prerequisites

- A Proxmox VE node reachable on your LAN, with an Ubuntu Server ISO
  (26.04) already uploaded to its ISO storage.
- Two Proxmox API tokens, each scoped to least privilege for what it does:
  one for Packer (template builds), one for Terraform (clone/configure the
  VMs). See [`docs/PACKER.md`](docs/PACKER.md) for the exact `pveum`
  commands to create the Packer token; Terraform's token setup is in
  [`docs/TERRAFORM.md`](docs/TERRAFORM.md).
- `age` and `sops` installed, plus a `secrets.yaml` at the repo root holding
  the Proxmox tokens and any other credentials the `.envrc` files decrypt
  per directory — see "Secrets management" below for how to set this up.
- `direnv` installed and hooked into your shell.
- `pre-commit` installed if you plan to commit changes (see
  [`CONTRIBUTING.md`](CONTRIBUTING.md)).
- A Cloudflare API token scoped to the `bcochofel.com` zone — **Zone → DNS →
  Edit** + **Zone → Zone → Read** permissions, "Include: Specific zone:
  bcochofel.com" — for Caddy's Let's Encrypt DNS-01 challenge. Create a
  dedicated token for this repo; don't reuse one from another repo.

### Secrets management (SOPS + age)

Every credential this repo needs — Proxmox API tokens, the cloud-init
password hash, the Cloudflare token — lives in one file, `secrets.yaml` at
the repo root, encrypted at rest with [SOPS](https://github.com/getsops/sops)
using an [age](https://github.com/FiloSottile/age) key. Unlike most
`secrets.*` naming conventions, **this file is meant to be committed** —
SOPS encrypts the values in place, so the file in git is ciphertext, safe to
version alongside the code that needs it. What must never be committed is
the age *private* key or a decrypted copy of the file — both are covered by
`.gitignore`.

**First-time setup (generating your own age key):**

```bash
age-keygen -o ~/.config/sops/age/keys.txt
chmod 600 ~/.config/sops/age/keys.txt
```

This prints an age public key (`age1...`). Paste it into [`.sops.yaml`](.sops.yaml)
as the recipient (replacing the placeholder there) before creating
`secrets.yaml` for the first time.

**Creating or editing `secrets.yaml`:**

```bash
sops secrets.yaml
```

This decrypts into a temp file, opens your `$EDITOR`, and re-encrypts on
save. If the file doesn't exist yet, SOPS creates it fresh. Add these keys:

| Key | Used by |
| --- | --- |
| `proxmox_packer_token_id` / `proxmox_packer_token_secret` | Packer |
| `proxmox_terraform_token_id` / `proxmox_terraform_token_secret` | Terraform |
| `tf_cloud_token` | Terraform (HCP Terraform) |
| `cloudinit_password` | Packer + Terraform (cloud-init user password) |
| `cloudflare_api_token` | Ansible (Caddy's DNS-01 ACME) |
| `pihole_webpassword` | Ansible (Pihole admin UI password) |

The ACME account contact email isn't a secret — it's set directly as
`letsencrypt_email` in `ansible/inventory/group_vars/all.yml`, not routed
through `secrets.yaml`.

**Viewing decrypted content (read-only):**

```bash
sops -d secrets.yaml
```

**How `direnv` uses it:** each directory's `.envrc` runs
`sops -d --output-type dotenv secrets.yaml` and exports the result as
environment variables (`PKR_VAR_*` for Packer, `TF_VAR_*` for Terraform,
`CLOUDFLARE_API_TOKEN`/`PIHOLE_WEBPASSWORD` for Ansible). Once `secrets.yaml`
exists and your age key can decrypt it, `direnv allow` (via `make install`)
is all that's needed for those variables to appear automatically when you
`cd` into `packer/`, `terraform/`, etc.

**After editing `secrets.yaml` itself:** no action needed — direnv re-runs
`.envrc` automatically the next time you `cd` into a directory, or
immediately via `direnv reload`.

**After editing any `.envrc` file:** direnv treats a changed `.envrc` as
untrusted and blocks it until re-approved:

```bash
make direnv-allow
```

### 0. Prepare the local environment

```bash
make install
```

Pins the CLI binaries this repo needs (`terraform`, `packer`, `trivy`,
`tflint`, `terraform-docs`, `sops`) into `~/bin`, approves the `.envrc`
files (root, `packer/`, `terraform/`, `ansible/`) via direnv, and creates
the `.venv/` Ansible runs from.

### 1. Build the VM template (Packer)

```bash
make packer-init
cd packer/ubuntu-26.04
cp variables.pkrvars.hcl.example variables.auto.pkrvars.hcl   # fill in, gitignored, auto-loaded
packer build .
```

See [`packer/ubuntu-26.04/README.md`](packer/ubuntu-26.04/README.md) for
what it bakes in and why.

### 2. Clone the VM and generate the inventory (Terraform)

```bash
cd terraform
cp example.tfvars terraform.tfvars   # edit, or set the equivalent HCP workspace variables
terraform init    # one time
terraform plan    # review before applying
terraform apply
```

This clones the Packer template into the `proxy` and `dns` VMs, assigns
each a static IP, and writes `ansible/inventory/hosts.ini` — see
[`docs/TERRAFORM.md`](docs/TERRAFORM.md), including the `pveum` commands to
create the `terraform@pve` token if you haven't already.

### 3. Configure everything (Ansible)

```bash
source .venv/bin/activate   # from repo root
cd ansible
ansible-galaxy collection install -r requirements.yml
ansible-playbook playbooks/site.yml
```

Runs bootstrap -> DNS (macvlan network, CoreDNS, Pihole) -> Caddy (builds
the image via `xcaddy`, renders the Caddyfile, brings up the container) ->
health check. See [`docs/ANSIBLE.md`](docs/ANSIBLE.md) for the role/
playbook breakdown.

**Before this succeeds:** `CLOUDFLARE_API_TOKEN` and `PIHOLE_WEBPASSWORD`
must be set in `secrets.yaml` and exported from `ansible/.envrc` — a
preflight check fails loudly and early if either is missing.

Once done, see [Verify](#verify) below.

### Migration cutover (retiring the QNAP-hosted CoreDNS/Pihole)

This is a real cutover, not a hot swap — the new `dns` VM uses different
IPs (`192.168.68.42`/`.43`) than the QNAP containers it replaces
(`.5`/`.6`), deliberately, so both can run side by side during migration:

1. Provision and verify the `dns` VM (above) — confirm `dig @192.168.68.42
   nas.homelab.bcochofel.com` and `dig @192.168.68.43
   nas.homelab.bcochofel.com` both resolve correctly, and the Pihole
   admin UI (see [Web UIs](#web-uis) below) is reachable.
2. Point your router/DHCP server's DNS settings at `.42`/`.43` instead of
   the QNAP's `.5`/`.6`.
3. Once every client has picked up the new servers (DHCP lease renewal, or
   a manual flush), stop and remove the CoreDNS/Pihole containers in QNAP
   Container Station.

### Adding a proxied site

Edit `caddy_sites` in `ansible/inventory/group_vars/all.yml` (add an
`fqdn`/`upstream` pair, optionally `insecure_skip_verify: true` if the
upstream presents a self-signed cert), point that fqdn's DNS record at the
Caddy VM's IP (see [DNS](#dns) below), then re-run
`ansible-playbook playbooks/site.yml` — the Caddyfile template loops over
this list, so no role changes needed.

## Topology

| VM    | vCPU | RAM  | Disk | Role                | IP                            |
| ----- | ---- | ---- | ---- | ------------------- | ----------------------------- |
| proxy | 1    | 1 GB | 20 G | Caddy reverse proxy | 192.168.68.40                 |
| dns   | 2    | 2 GB | 20 G | CoreDNS + Pihole    | 192.168.68.41 (.42/.43 below) |

`proxy` runs a single-container Docker Compose stack — Caddy, built from a
role-rendered `Dockerfile` with the `caddy-dns/cloudflare` module compiled
in via `xcaddy`, so it can issue its own Let's Encrypt certs via Cloudflare
DNS-01 with no certbot/timer/deploy-hook needed.

`dns` runs two Docker Compose services, CoreDNS and Pihole, each attached
to a shared Docker macvlan network with its own real LAN IP —
`192.168.68.42` (CoreDNS, `ns1`) and `192.168.68.43` (Pihole, `ns2`) — so
both independently answer on port 53 (true redundancy, not one chained
behind the other). `192.168.68.41` is just the VM's own management IP for
SSH/Ansible, not a DNS-serving address.

## DNS

This repo *does* manage DNS now — the `dns` VM (see above) replaces the
CoreDNS + Pihole containers that used to run in QNAP Container Station
(`.5`/`.6`; see "Migration cutover" above). `ansible/inventory/group_vars/
dns.yml`'s `dns_hosts` list is the single source of truth for the local
zone, rendered into both CoreDNS's `hosts.local` and Pihole's
`FTLCONF_dns_hosts` env var — edit that list (not either container
directly) to add or change a hostname. Every fqdn Caddy manages
(`caddy_sites` in `group_vars/all.yml`) resolves to Caddy's IP
(`192.168.68.40`) here, not its backend — see "Adding a proxied site"
above.

What this repo still does *not* do: touch your router/DHCP server's DNS
settings (a manual step, see "Migration cutover"), or manage the public
`bcochofel.com` Cloudflare zone (only used for the ACME DNS-01 TXT
challenge, not a resolvable public A/AAAA record for any of these
LAN-only hostnames).

## Web UIs

The only web UI this repo stands up itself (not proxied to another
system) is Pihole's:

| UI | URL | Login |
| --- | --- | --- |
| Pihole (`ns2`) | <http://192.168.68.43/admin> | Password-only (no username) — the `pihole_webpassword` value from `secrets.yaml` |

Pihole's self-signed cert means `https://` will warn in the browser; `http://`
is what "Migration cutover" above uses too. Caddy and CoreDNS have no web UI
of their own — Caddy's whole job is fronting *other* systems' UIs
(`nas`/`www`/`pve1` in `caddy_sites`, all of which depend on
something outside this repo), and CoreDNS only exposes a Prometheus metrics
endpoint (`:9153`), not a dashboard.

## Verify

- `https://nas.homelab.bcochofel.com`, `https://www.homelab.bcochofel.com`,
  `https://pve1.homelab.bcochofel.com` — each should present a real Let's
  Encrypt certificate (issued by Caddy itself) and proxy to its backend.
  (`kibana.homelab.bcochofel.com` omitted here — its backend lives in the
  separate `homelab-proxmox-elastic` repo, so it's only reachable once
  that stack is deployed too.)
- Caddy container: `docker ps` on the `proxy` VM should show `caddy`
  healthy.
- `dig @192.168.68.42 <any dns_hosts fqdn>` and
  `dig @192.168.68.43 <any dns_hosts fqdn>` — both CoreDNS and Pihole
  should answer independently. `docker ps` on the `dns` VM should show
  both `coredns` and `pihole` healthy.

## Design decisions

- **Provider:** `bpg/proxmox`.
- **State:** HCP Terraform, workspace `core-caddy`.
- **Caddy runtime:** Docker Compose, image built via `xcaddy` at deploy
  time (not a stock `caddy` image) so the `caddy-dns/cloudflare` module is
  available.
- **TLS:** Caddy's native ACME, DNS-01 via Cloudflare — no certbot.
- **DNS runtime:** CoreDNS + Pihole, two Docker Compose services on one VM,
  each on its own Docker macvlan IP for independent `ns1`/`ns2`
  redundancy — not chained behind each other.
- **Inventory:** only `ansible/inventory/hosts.ini` is generated.
  `ansible/inventory/group_vars/` is hand-authored and never overwritten.
- **Decoupling:** Terraform and Ansible are run as separate, explicit
  commands — no `local-exec` chaining, no Makefile wrapper around either
  write step.
- **Template:** `ubuntu-26.04`, minimal (Docker only).

## Documentation

- [`docs/PACKER.md`](docs/PACKER.md) — VM template build.
- [`docs/TERRAFORM.md`](docs/TERRAFORM.md) — cloning the VM + inventory generation.
- [`docs/ANSIBLE.md`](docs/ANSIBLE.md) — Caddy configuration.
- [`CONTRIBUTING.md`](CONTRIBUTING.md) — environment setup, branching, commit
  conventions, and versioning for contributors.
- [`TODO.md`](TODO.md) — phase-by-phase roadmap and current status.

## References

- [Proxmox VE Documentation](https://pve.proxmox.com/pve-docs/)
- [Proxmox Cloud-Init Support](https://pve.proxmox.com/wiki/Cloud-Init_Support)
- [Caddy Documentation](https://caddyserver.com/docs/)
- [caddy-dns/cloudflare](https://github.com/caddy-dns/cloudflare)
