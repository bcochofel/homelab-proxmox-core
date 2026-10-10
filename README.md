# homelab-proxmox-core

[![Version][badge-version]][releases]
[![CI][badge-ci]][ci]
[![pre-commit][badge-pre-commit]](.pre-commit-config.yaml)
[![Packer][badge-packer]](docs/PACKER.md)
[![OpenTofu][badge-opentofu]](docs/TERRAFORM.md)
[![Ansible][badge-ansible]](docs/ANSIBLE.md)

<!-- The tool versions are read from the files that pin them (mise.toml,
requirements.txt), so these badges never need editing. -->
[badge-version]: https://img.shields.io/github/v/release/BCochofelHomelab/homelab-proxmox-core?label=version
[releases]: https://github.com/BCochofelHomelab/homelab-proxmox-core/releases
[badge-ci]: https://img.shields.io/github/actions/workflow/status/BCochofelHomelab/homelab-proxmox-core/ci.yml?label=CI&logo=github
[ci]: https://github.com/BCochofelHomelab/homelab-proxmox-core/actions/workflows/ci.yml
[badge-pre-commit]: https://img.shields.io/badge/pre--commit-enabled-brightgreen?logo=pre-commit
[badge-packer]: https://img.shields.io/badge/dynamic/toml?url=https%3A%2F%2Fraw.githubusercontent.com%2FBCochofelHomelab%2Fhomelab-proxmox-core%2Fmain%2Fmise.toml&query=%24.tools.packer&label=Packer&logo=packer&color=02A8EF
[badge-opentofu]: https://img.shields.io/badge/dynamic/toml?url=https%3A%2F%2Fraw.githubusercontent.com%2FBCochofelHomelab%2Fhomelab-proxmox-core%2Fmain%2Fmise.toml&query=%24.tools.opentofu&label=OpenTofu&logo=opentofu&color=844FBA
[badge-ansible]: https://img.shields.io/badge/dynamic/regex?url=https%3A%2F%2Fraw.githubusercontent.com%2FBCochofelHomelab%2Fhomelab-proxmox-core%2Fmain%2Frequirements.txt&search=%5Cnansible%28%3E%3D%5B0-9.%5D%2B%29&replace=%241&label=Ansible&logo=ansible&color=1A1918

Three VMs on Proxmox, built with an IaC pipeline: `proxy` (Caddy reverse
proxy), `server01` (CoreDNS + primary Pi-hole; Ansible inventory group
`dns`) and `runner01`, the self-hosted GitHub Actions runner that dry-runs
pull requests ([`docs/SETUP.md`](docs/SETUP.md#stage-8-the-dry-run-runner-optional)).
The DNS secondaries, CoreDNS and Pi-hole, run in QNAP Container Station
and are set up by hand, see [Test DNS and configure your
network](#test-dns-and-configure-your-network).

```text
Packer (template)  ->  Terraform (clone VMs + generate inventory)  ->  Ansible (configure)
```

## Homelab architecture

![Homelab network architecture](docs/diagrams/architecture.png)

Editable source: [`docs/diagrams/architecture.drawio`](docs/diagrams/architecture.drawio)
(open in [app.diagrams.net](https://app.diagrams.net)).

This repo is one of two that make up the homelab:

- **`homelab-proxmox-core`** (this repo) — edge routing and name
  resolution: the Caddy reverse proxy and the CoreDNS + Pihole DNS pair.
- **[`homelab-proxmox-workloads`](https://github.com/BCochofelHomelab/homelab-proxmox-workloads)**
  — every workload that runs behind it, managed with OpenTofu and
  Terramate.

### Why it's built this way

Both repos follow Google's
[*AI engineering for reliable operations*](https://sre.google/resources/practices-and-processes/ai-engineering-reliable-operations/):
an AI agent helps operate the homelab, gaining autonomy step by step, and
only within guardrails that hold even when the agent gets something wrong.
Much of what may look like extra ceremony here follows from that:

| Guideline from the paper | How it shows up in this repo |
| --- | --- |
| No ambient access | Nothing is exported into your shell; each `mise run` task decrypts one file for one command ([`docs/CREDENTIALS.md`](docs/CREDENTIALS.md)). |
| Least privilege, one identity per role | Separate Proxmox tokens for Packer, for applying, and for the agent's read-only work. The agent has no HCP token at all: the Free plan can't issue a read-only one. |
| The agent reads, humans change | The agent has only the `ai-agent` age key, which opens the read-only credentials and nothing else. |
| Dry-run before any change | Every pull request touching `terraform/` or `ansible/` gets `tofu plan` and `ansible-playbook --check` on a self-hosted runner, after your approval; apply stays a human step ([`docs/SETUP.md`](docs/SETUP.md#stage-8-the-dry-run-runner-optional)). |
| Boundaries enforced by construction | The devcontainer holds only the read-only credentials ([`docs/DEVCONTAINER.md`](docs/DEVCONTAINER.md)). |

The roadmap for the rest of the paper (audit trail, alerting, the
autonomy levels from assisted investigation to bounded auto-remediation)
is [`docs/SRE-AI.md`](docs/SRE-AI.md), with where each item stands.

## Quickstart

Building it, or rebuilding it from nothing, GitHub organization included,
is [`docs/SETUP.md`](docs/SETUP.md): every stage in order, each with its
check. In short, once the workstation, accounts and credentials are in
place ([`docs/CREDENTIALS.md`](docs/CREDENTIALS.md)):

```bash
mise trust && mise install   # the pinned toolchain
mise run packer:build        # 1. the VM template
mise run tofu:init           # 2. the VMs and the inventory
mise run tofu:plan           #    review it
mise run tofu:apply
mise run ansible:site        # 3. configure everything
```

Day to day, every change goes through a pull request:
[`CONTRIBUTING.md`](CONTRIBUTING.md).

## Test DNS and configure your network

### Who does what

Two layers, each with a primary and a secondary. "Primary/secondary"
means something different in each:

| Server | IP | Host | Role |
| --- | --- | --- | --- |
| CoreDNS `ns1` | `192.168.68.2` | `server01` | **Authoritative primary** for `homelab.bcochofel.com`: serves the zone from `dns_hosts` and pushes every change to the secondary (AXFR + NOTIFY). Forwards every other name to `1.1.1.1`/`8.8.8.8` |
| CoreDNS `ns2` | `192.168.68.3` | QNAP NAS | **Authoritative secondary**: a read-only copy of the same zone, pulled from `ns1`, with the same forwarders. Runs in Container Station, set up by hand: [`docs/EXTERNAL-DEPENDENCIES.md`](docs/EXTERNAL-DEPENDENCIES.md#coredns-secondary) |
| Pi-hole | `192.168.68.5` | `server01` | **Primary resolver** for clients: ad-blocking, forwards `homelab.bcochofel.com` to `ns1`/`ns2` and everything else to `1.1.1.1`/`8.8.8.8` |
| Pi-hole | `192.168.68.6` | QNAP NAS | **Secondary resolver**: same settings as `.5` (from the same Ansible variables), so clients get the same answers from either. Runs in Container Station, set up by hand: [`docs/EXTERNAL-DEPENDENCIES.md`](docs/EXTERNAL-DEPENDENCIES.md#pi-hole-secondary) |

- **Authoritative** means CoreDNS *owns* the `homelab.bcochofel.com`
  records and answers for them with authority. That subdomain exists only
  on these servers: it isn't published in the public `bcochofel.com`
  zone, so a client using `1.1.1.1` directly can't resolve it.
- **CoreDNS is also a full resolver.** For any name outside the local
  subdomain it forwards to its own upstreams, `1.1.1.1` and `8.8.8.8`
  (`dns_forward_resolvers`), with a cache. It answers only clients in
  `192.168.68.0/22`.
- The **Pi-holes** own no records. They're what clients talk to: they
  check blocklists, forward any `homelab.bcochofel.com` name to CoreDNS
  (`ns1` and `ns2`, via Pi-hole's conditional forwarding,
  `FTLCONF_dns_revServers`), and send everything else straight to the
  same `1.1.1.1`/`8.8.8.8` upstreams — not through CoreDNS.

So, from a client's point of view:

```text
client ─► Pi-hole (.5 / .6) ─┬─ blocklisted?          ─► 0.0.0.0
                             ├─ *.homelab.bcochofel.com ─► CoreDNS ns1 (.2) / ns2 (.3)
                             └─ anything else          ─► 1.1.1.1 / 8.8.8.8

client ─► CoreDNS (.2 / .3) ─┬─ *.homelab.bcochofel.com ─► answered from the zone
   (bypassing Pi-hole)       └─ anything else          ─► 1.1.1.1 / 8.8.8.8
```

Both QNAP secondaries must be set up
([`docs/EXTERNAL-DEPENDENCIES.md`](docs/EXTERNAL-DEPENDENCIES.md)) before every check
below can pass.

### Test the servers

Run these from a LAN machine, **not** from `server01` itself: Docker's
macvlan driver blocks a host from reaching its own containers' IPs, so
`.2` and `.5` never answer from `server01`.

```bash
# 1. Authoritative answers. Both should return 192.168.68.16 with the "aa"
#    (authoritative answer) flag.
dig @192.168.68.2 nas.homelab.bcochofel.com
dig @192.168.68.3 nas.homelab.bcochofel.com

# 2. Primary and secondary hold the same zone: identical serial numbers.
dig @192.168.68.2 homelab.bcochofel.com SOA +short
dig @192.168.68.3 homelab.bcochofel.com SOA +short

# 3. Both Pi-holes resolve local names (forwarded to CoreDNS, so no "aa")...
dig @192.168.68.5 nas.homelab.bcochofel.com +short
dig @192.168.68.6 nas.homelab.bcochofel.com +short

# 4. ...and the internet...
dig @192.168.68.5 example.com +short
dig @192.168.68.6 example.com +short

# 5. ...and block ads: a blocklisted domain returns 0.0.0.0.
dig @192.168.68.5 doubleclick.net +short
dig @192.168.68.6 doubleclick.net +short

# 6. CoreDNS forwards internet names itself (what bypassing Pi-hole relies on),
#    and doesn't block ads: this returns a real address.
dig @192.168.68.2 example.com +short
dig @192.168.68.3 example.com +short
dig @192.168.68.2 doubleclick.net +short
```

If the serials in check 2 differ, the secondary hasn't picked up the latest
change yet; check `docker logs coredns-secondary` on the NAS. CoreDNS also
refuses queries from outside `192.168.68.0/22`, which you can only see from
a client on another subnet.

### Configure your network

1. **Router / DHCP server:** set the DNS servers handed to clients to
   **`192.168.68.5`** (primary) and **`192.168.68.6`** (secondary): the two
   Pi-holes. Don't hand out a CoreDNS address alongside them: clients
   don't reliably prefer the first server, so a mixed pair makes
   ad-blocking hit or miss.
2. **Search domain** (optional): if the DHCP server can set one (DHCP
   option 15), use `homelab.bcochofel.com` so short names like `nas`
   resolve.
3. **Renew the lease on a client** (reconnect, or `sudo dhclient -r && sudo
   dhclient` on Linux), then check it uses the Pi-holes: `resolvectl
   status` on Linux, `ipconfig /all` on Windows. `nslookup
   nas.homelab.bcochofel.com` should return `192.168.68.16`, and the
   query should appear in the Pi-hole query log.
4. **Hosts with static DNS settings** don't pick this up from DHCP; set
   them to `.5`/`.6` by hand. The VMs this repo builds are already
   configured by cloud-init (OpenTofu's `nameserver` variable), except
   `server01`, which has to use public resolvers because it can't reach
   its own containers.

**Bypassing Pi-hole:** because CoreDNS forwards everything outside the
local subdomain itself, a device (or the whole network) can use CoreDNS
directly — set its DNS servers to `192.168.68.2` and `192.168.68.3`. It
still resolves local and internet names, just without ad-blocking. Check 6
above confirms both CoreDNS servers forward; `ns2`'s configuration lives
on the NAS, outside this repo, so it's the one to watch.

## Adding a proxied site

Edit `caddy_sites` in `ansible/inventory/group_vars/all.yml` (add an
`fqdn`/`upstream` pair, optionally `insecure_skip_verify: true` if the
upstream presents a self-signed cert), point that fqdn's DNS record at the
Caddy VM's IP (see [DNS](#dns) below), then re-run
`mise run ansible:site` — the Caddyfile template loops over
this list, so no role changes needed.

## Topology

| VM       | vCPU | RAM  | Disk | Role                                | IP                          |
| -------- | ---- | ---- | ---- | ----------------------------------- | --------------------------- |
| proxy    | 1    | 1 GB | 50 G | Caddy reverse proxy                 | 192.168.68.16               |
| server01 | 2    | 2 GB | 50 G | CoreDNS + Pihole primary            | 192.168.68.15 (.2/.5 below) |
| runner01 | 2    | 4 GB | 50 G | GitHub Actions runner (CI dry-runs) | 192.168.68.9                |

(`server01` is the VM's Proxmox name/hostname — the Ansible inventory
group is still `dns`. `runner01` is in group `github_runner`:
[`docs/SETUP.md`](docs/SETUP.md#stage-8-the-dry-run-runner-optional).) The DNS secondaries aren't in this table since
neither is a Terraform-managed VM: CoreDNS (`192.168.68.3`) and Pihole
(`192.168.68.6`) run in Container Station on the user's QNAP NAS — see
"Test DNS and configure your network" above.

`proxy` runs a single-container Docker Compose stack — Caddy, built from a
role-rendered `Dockerfile` with the `caddy-dns/cloudflare` module compiled
in via `xcaddy`, so it can issue its own Let's Encrypt certs via Cloudflare
DNS-01 with no certbot/timer/deploy-hook needed.

`server01` runs two Docker Compose services, CoreDNS and Pihole, each
attached to a shared Docker macvlan network with its own real LAN IP —
`192.168.68.2` (CoreDNS, authoritative primary for `homelab.bcochofel.com`)
and `192.168.68.5` (Pihole primary, ad-blocking + conditional-forward).
These aren't independent peers: Pihole forwards the local zone to CoreDNS
rather than holding its own copy.
`192.168.68.15` is just the VM's own management IP for SSH/Ansible, not a
DNS-serving address. The secondaries, CoreDNS (`.3`) and Pihole (`.6`),
run in QNAP Container Station, each with its own LAN IP through QNAP's
`qnet` driver.

## DNS

This repo manages DNS. `ansible/inventory/group_vars/dns.yml`'s
`dns_hosts` list is the single source of truth for the local zone
(`dns_zone: homelab.bcochofel.com`), rendered into CoreDNS's zone file
(`db.<zone>`, served by the `file` plugin) — edit that list, not either
container directly, to add or change a hostname. CoreDNS transfers the
zone via AXFR to a secondary running on the user's QNAP NAS
(`coredns_secondary_ip`, outside this repo's reach). Neither Pihole
instance (primary on `server01`, secondary on the QNAP) holds its own copy
of the zone — both conditionally forward `homelab.bcochofel.com` queries
to both CoreDNS instances (`FTLCONF_dns_revServers`) and otherwise only do
ad-blocking, using the same external resolvers (`dns_forward_resolvers`)
as CoreDNS's catch-all block; `inventory/group_vars/pihole.yml` is the
single source of truth for settings both Pihole instances share (the
secondary copies them by hand, see
[`docs/EXTERNAL-DEPENDENCIES.md`](docs/EXTERNAL-DEPENDENCIES.md#pi-hole-secondary)). Both CoreDNS instances restrict queries to
`192.168.68.0/22` via the `acl` plugin. Every fqdn Caddy manages
(`caddy_sites` in `group_vars/all.yml`) resolves to Caddy's IP
(`192.168.68.16`) here, not its backend — see "Adding a proxied site"
above.

What this repo still does *not* do: touch your router/DHCP server's DNS
settings (a manual step, see "Test DNS and configure your network"),
manage the QNAP-hosted secondaries (set up by hand, see
[`docs/EXTERNAL-DEPENDENCIES.md`](docs/EXTERNAL-DEPENDENCIES.md)), or manage the public `bcochofel.com`
Cloudflare zone (only used for the ACME DNS-01 TXT challenge, not a
resolvable public A/AAAA record for any of these LAN-only hostnames).

## Web UIs

The only web UI this repo stands up itself (not proxied to another
system) is Pihole's:

| UI | URL | Login |
| --- | --- | --- |
| Pihole (primary) | <http://192.168.68.5/admin> | Password-only (no username) — the `pihole_webpassword` value from `ansible/inventory/group_vars/pihole.sops.yaml` |
| Pihole (secondary, QNAP) | <http://192.168.68.6/admin> | The password you set with `pihole setpassword` ([`docs/EXTERNAL-DEPENDENCIES.md`](docs/EXTERNAL-DEPENDENCIES.md#pi-hole-secondary)) |

Pihole's self-signed cert means `https://` will warn in the browser; use
`http://`. Caddy and CoreDNS have no web UI
of their own — Caddy's whole job is fronting *other* systems' UIs
(`nas`/`www`/`pve1`/`ha` in `caddy_sites`, all of which depend on
something outside this repo), and CoreDNS only exposes a Prometheus metrics
endpoint (`:9153`), not a dashboard.

## Verify

- `https://nas.homelab.bcochofel.com`, `https://www.homelab.bcochofel.com`,
  `https://pve1.homelab.bcochofel.com`, `https://ha.homelab.bcochofel.com`,
  `https://kibana.homelab.bcochofel.com` — each should present a real Let's Encrypt certificate (issued by Caddy
  itself) and proxy to its backend. The backends are external
  dependencies; Home Assistant needs a one-time proxy setting first, see
  [`docs/EXTERNAL-DEPENDENCIES.md`](docs/EXTERNAL-DEPENDENCIES.md#home-assistant).
- The playbook's last task lists every external dependency that isn't
  ready yet.
- Caddy container: `docker ps` on the `proxy` VM should show `caddy`
  healthy.
- `docker ps` on the `server01` VM should show both `coredns` and
  `pihole` healthy. The QNAP secondaries are checked from the NAS, see
  their docs.
- DNS: run the checks in
  [Test DNS and configure your network](#test-dns-and-configure-your-network).

## Design decisions

- **Provider:** `bpg/proxmox`. VM IDs are not hardcoded — `caddy_node`/
  `dns_node`/`runner_node`'s `vmid` is optional, so Proxmox auto-assigns the next
  available ID on first create; once a VM exists, its ID stays put
  (`vm_id` is Optional+Computed) even though config doesn't pin it.
- **State:** HCP Terraform, workspace `core-caddy`.
- **Caddy runtime:** Docker Compose, image built via `xcaddy` at deploy
  time (not a stock `caddy` image) so the `caddy-dns/cloudflare` module is
  available.
- **TLS:** Caddy's native ACME, DNS-01 via Cloudflare — no certbot.
- **DNS runtime:** CoreDNS is the authoritative primary for
  `homelab.bcochofel.com` (`file`+`transfer`+`acl` plugins), with a
  QNAP-hosted secondary pulling the zone via AXFR for read redundancy.
  Pihole is deliberately chained behind CoreDNS for the local zone
  (conditional forwarding via `FTLCONF_dns_revServers`) while remaining an
  independent ad-blocking resolver for everything else.
- **Pihole runtime:** two instances with the same settings
  (`ansible/inventory/group_vars/pihole.yml`, not live gravity.db/
  blocklist sync) — a primary on `server01` (macvlan, Ansible-managed) and
  a secondary in QNAP Container Station (set up by hand).
- **Inventory:** only `ansible/inventory/hosts.ini` is generated.
  `ansible/inventory/group_vars/` and `proxmox.ini` (the Proxmox nodes)
  are hand-authored and never overwritten.
- **Decoupling:** Terraform and Ansible are run as separate, explicit
  commands — no `local-exec` chaining, no mise task wrapping either
  write step.
- **Template:** `ubuntu-26.04`, minimal: Docker, plus Elastic Agent installed
  but not enrolled and disabled until there's a stack to enroll into.

## Documentation

- [`docs/SETUP.md`](docs/SETUP.md) — building everything from nothing, or
  rebuilding it, in order: the workstation, the GitHub organization, the
  accounts, the build, the network, the AI agent, the dry-run runner and
  the [red button](docs/SETUP.md#red-button) that stops both.
- [`docs/CREDENTIALS.md`](docs/CREDENTIALS.md) — the
  [secret tiers](docs/CREDENTIALS.md#secret-tiers), and how to create
  every credential and where it's stored.
- [`docs/PACKER.md`](docs/PACKER.md) — VM template build.
- [`docs/TERRAFORM.md`](docs/TERRAFORM.md) — cloning the VM + inventory generation.
- [`docs/ANSIBLE.md`](docs/ANSIBLE.md) — Caddy, CoreDNS, and Pihole
  configuration.
- [`docs/DEVCONTAINER.md`](docs/DEVCONTAINER.md) — the devcontainer that
  runs the AI agent with only the read-only credentials.
- [`docs/EXTERNAL-DEPENDENCIES.md`](docs/EXTERNAL-DEPENDENCIES.md) — what
  this repo relies on but doesn't deploy, set up by hand: the CoreDNS and
  Pi-hole secondaries on the QNAP, and Home Assistant.
- [`CONTRIBUTING.md`](CONTRIBUTING.md) — how a change flows from a pull
  request (yours or the AI agent's) through CI, the dry-run, review and
  release to an apply; branches, commits, checks, and the toolchain.
- [`docs/SRE-AI.md`](docs/SRE-AI.md) — the homelab-wide SRE AI-autonomy
  roadmap and its status, with checkboxes (this repo +
  `homelab-proxmox-workloads`).

## References

- [Proxmox VE Documentation](https://pve.proxmox.com/pve-docs/)
- [Proxmox Cloud-Init Support](https://pve.proxmox.com/wiki/Cloud-Init_Support)
- [Caddy Documentation](https://caddyserver.com/docs/)
- [caddy-dns/cloudflare](https://github.com/caddy-dns/cloudflare)
- [Trunk-based development](https://trunkbaseddevelopment.com/) — the
  branching model: short-lived branches merged into `main`
- [Conventional Branch](https://conventionalbranch.org/) — branch naming
  (see [`CONTRIBUTING.md`](CONTRIBUTING.md))
- [Conventional Commits](https://www.conventionalcommits.org/) — commit
  messages and release versioning
- [Semantic Versioning](https://semver.org/) — the version scheme releases
  follow
- [semantic-release](https://semantic-release.gitbook.io/) — computes and
  publishes releases from the commit history
- [pre-commit](https://pre-commit.com/) — the git hook framework running
  the checks in `.pre-commit-config.yaml`
