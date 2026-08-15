# Ansible — Caddy + DNS configuration

Third stage of the pipeline: configures the VMs Terraform just cloned. Run
from `ansible/`, using the repo-root `.venv/` (`make ansible-install`
pins `ansible`/`ansible-lint`; `ansible-galaxy collection install -r
requirements.yml` pulls `community.docker` and `ansible.utils`).

```bash
cd ansible
../.venv/bin/ansible-galaxy collection install -r requirements.yml
../.venv/bin/ansible-playbook playbooks/site.yml
```

## Roles

- **`common`** — preflight checks, plus a Docker install for hosts this
  repo didn't provision (`roles/common/tasks/install_docker.yml`, only
  when `docker_preinstalled: false` — set in `group_vars/pi3.yml` for
  pi3-01; every Packer-built VM defaults to `true` and skips it). Then
  `asserts.yml`: confirms the host is Ubuntu >= 22.04 or Debian/Raspbian
  (no version floor for those — Raspberry Pi OS versions don't map to
  Ubuntu's scheme), Docker + the Compose plugin are present, and, for the
  `caddy`/`pihole` groups specifically, that `cloudflare_api_token`/
  `pihole_webpassword` resolved non-empty from the environment. Fails
  loudly and early rather than letting the `caddy`/`pihole` roles' own
  preflights fail later with a less obvious error.
- **`dns_network`** — one task
  (`community.docker.docker_network`): creates the shared Docker macvlan
  network (`dns_macvlan_network` in `inventory/group_vars/dns.yml`) both
  `coredns` and `pihole` attach to, giving each its own real LAN IP so
  both independently answer on port 53. Applied first, before either
  compose project references the network as `external`.
- **`coredns`** — renders and brings up CoreDNS as an authoritative
  primary for `dns_zone`, with a QNAP-hosted secondary pulling the zone
  via AXFR:
  1. `templates/Corefile.j2` — **two server blocks**. `{{ dns_zone }}:53`
     is authoritative: `acl` (restricts to `dns_macvlan_subnet`, i.e.
     `192.168.68.0/22`), `file` (serves the zone file below, with
     `reload 30s`), `transfer { to coredns_secondary_ip }` (answers the
     QNAP secondary's AXFR pulls and sends it NOTIFY on change). `.:53` is
     the recursive catch-all — same shape as before (`acl`, `health`,
     `prometheus`, `cache`, `forward`, `log`, `loadbalance`), with
     `forward` targets parametrized by `dns_forward_resolvers`.
     `health`/`prometheus` only live in the catch-all block (each opens
     its own listener; duplicating one across blocks fails to start).
     Plugin syntax confirmed against `https://coredns.io/plugins/`
     (2026-08-15).
  2. `templates/db.zone.j2` — an RFC1035 zone file (`$ORIGIN`, SOA with a
     Unix-timestamp serial, NS records for `ns1`/`ns2`, one A record per
     `dns_hosts` entry) — the single source of truth for the local zone.
     Pihole no longer renders its own copy of this data.
  3. `templates/docker-compose.yml.j2` — pulls the pinned
     `coredns/coredns` image, mounts the Corefile + zone file, attaches to
     the external macvlan network at `coredns_ip` (`192.168.68.2`). No
     `HEALTHCHECK` — the official image is built `FROM scratch` (no
     shell/wget/curl to run one); see `99-healthcheck.yml` instead.

  No secrets involved — any change to the Corefile/zone file/compose file
  notifies the `Restart coredns` handler. The zone file's Unix-timestamp
  serial changes on every Ansible run by design, so this handler fires
  every run even when `dns_hosts` itself didn't change.
- **`pihole`** — applies to the `pihole` group (`dns` + `pi3` — both
  instances, primary and secondary), renders and brings up Pihole,
  ad-blocking only:
  1. `templates/env.j2` — `FTLCONF_webserver_api_password` (from
     `pihole_webpassword`), `TZ`, `FTLCONF_dns_upstreams` (from
     `dns_forward_resolvers`, used for everything outside `dns_zone`),
     `FTLCONF_dns_revServers` (two `;`-joined entries, one per CoreDNS
     instance — `<enabled>,<cidr>,<server>#<port>,<domain>` — conditionally
     forwards `dns_zone` queries to CoreDNS instead of Pihole holding its
     own copy; confirmed against
     `https://docs.pi-hole.net/ftldns/configfile/`, 2026-08-15), rendered
     to `.env` and loaded via `env_file:` — same secret-hygiene reasoning
     as Caddy's `CLOUDFLARE_API_TOKEN` (never templated straight into the
     compose file, so `docker inspect`/`docker compose config` can't leak
     it). `FTLCONF_dns_hosts` is deliberately **not** rendered any more —
     CoreDNS's zone file is now the sole source of truth for local
     records; one accepted trade-off is Pihole no longer auto-answers PTR
     lookups for these hosts, and CoreDNS has no reverse zone either. Every
     var this template uses comes from `group_vars/all.yml` or
     `group_vars/pihole.yml` (shared by both instances), never from the
     instance-specific `group_vars/dns.yml`/`group_vars/pi3.yml` — so both
     instances render byte-identical `.env` files.
  2. `templates/docker-compose.yml.j2` — pulls the pinned `pihole/pihole`
     image, `cap_add: NET_ADMIN`, `/etc/pihole` on a named volume so
     Pihole's own state (once it accumulates any) survives a recreate.
     Branches on `pihole_network_mode`: `macvlan` (server01 —
     `group_vars/dns.yml`) attaches to the external macvlan network at
     `pihole_ip` (`192.168.68.5`); `host` (pi3-01 — `group_vars/pi3.yml`,
     single-purpose Pi with no CoreDNS to share port 53 with) uses
     `network_mode: host` instead — no macvlan network to set up, and it
     sidesteps the macvlan-can't-reach-itself limitation entirely.

  Any change notifies the `Restart pihole` handler. Config parity between
  the two instances is achieved by Ansible variable sharing only — there's
  no gravity.db/blocklist replication (gravity-sync, Teleporter, etc. were
  considered and deliberately not built, see CLAUDE.md).
- **`caddy`** — renders and brings up the reverse proxy:
  1. `templates/Dockerfile.j2` — multi-stage `xcaddy build --with
     github.com/caddy-dns/cloudflare` against the pinned `caddy_version`,
     so the final image can do Cloudflare DNS-01 ACME natively — no
     certbot, no systemd timer, no deploy-hook.
  2. `templates/Caddyfile.j2` — one site block per entry in `caddy_sites`
     (`inventory/group_vars/all.yml`), each starting with a `tls { issuer
     acme { dns cloudflare {$CLOUDFLARE_API_TOKEN} \n resolvers
     <letsencrypt_dns_resolvers> } }` block (per-site, not the global
     `acme_dns` one-liner, and `resolvers` must be nested inside an
     explicit `issuer acme { }` — as a sibling of `dns` in either the
     global `acme_dns` option or the `tls { dns ... }` shorthand,
     `resolvers` is silently accepted by the Caddyfile parser but never
     reaches the running config, a real upstream Caddy limitation
     (`caddyserver/caddy` issues #4008/#7192), confirmed via Caddy's admin
     API config dump). `resolvers` matters because the `proxy` VM's own
     system resolver is CoreDNS, which is authoritative for
     `homelab.bcochofel.com`, so without it Caddy's ACME zone-cut
     discovery gets fooled into stopping at `homelab.bcochofel.com`
     instead of walking up to the real Cloudflare zone `bcochofel.com` —
     see CLAUDE.md. The explicit `issuer acme` also drops Caddy's default
     ZeroSSL fallback issuer (never part of this repo's design), followed
     by a plain `reverse_proxy` directive, with a `transport http { ... }`
     block added only when a site needs one:
     - `insecure_skip_verify: true` — upstream presents a self-signed cert
       on the LAN hop (e.g. the QNAP admin UI); doesn't weaken the
       public-facing TLS Caddy itself terminates.
     - `upstream_sni: <hostname>` — upstream is addressed by IP but
       presents a cert issued for its own hostname (Kibana's site entry
       uses this: Kibana already terminates its own Let's Encrypt cert via
       certbot, issued for `kibana.homelab.bcochofel.com`, not for the
       bare IP `192.168.68.33` — without `tls_server_name` set to that
       hostname, Caddy's default TLS verification checks the cert against
       the IP instead and fails). This is TLS bridging — two independent
       TLS sessions (client<->Caddy, Caddy<->Kibana), not a conflict.
  3. `templates/docker-compose.yml.j2` — builds the image from the two
     files above, publishes 80/443 (+443/udp for HTTP/3), and keeps
     `caddy_data`/`caddy_config` as named Docker volumes so issued certs
     survive a container recreate.
  4. `templates/env.j2` — `CLOUDFLARE_API_TOKEN`/`LETSENCRYPT_EMAIL`,
     rendered to `.env` and loaded via `env_file:`. The token is
     deliberately never templated straight into the Caddyfile, so `docker
     inspect`/`docker compose config` don't leak it the way a raw
     environment variable in the compose file would; the email rides along
     the same `{$VAR}` mechanism for consistency even though it isn't
     sensitive itself.

  No handler/notify dance here — `docker compose up -d --build` runs
  unconditionally every play (see the task comment for why: the
  `community.docker.docker_compose_v2` module used to hit a stale-image-
  reference race after old builds got garbage-collected; BuildKit's cache
  makes a no-op rebuild cheap anyway). That covers Dockerfile changes
  (image digest changes, `up` recreates the container) and
  docker-compose.yml changes (service definition changes, `up` recreates
  it) — but **not** Caddyfile or `.env` content changes: both are
  bind-mounted, not baked into the image, and `up` only diffs the service
  *definition*, never a bind-mounted file's *contents*. A separate task
  explicitly runs `docker compose restart caddy` when the Caddyfile/`.env`
  render tasks report `changed`, to actually pick up content-only changes
  (hit for real 2026-08-15 — a Caddyfile fix rendered correctly to disk
  but Caddy kept serving its old in-memory config until this was added).

## Adding or changing a proxied site

Edit `caddy_sites` in `inventory/group_vars/all.yml` — no role or template
change needed, the `Caddyfile.j2` loop picks up any new entry. Then:

1. Add a matching entry to `dns_hosts` in `inventory/group_vars/dns.yml`,
   pointed at Caddy's IP (`192.168.68.16`), not the backend — keeps the two
   lists in sync (nothing automates this).
2. Re-run `ansible-playbook playbooks/site.yml` (or just
   `ansible-playbook playbooks/05-dns.yml playbooks/10-caddy.yml` to skip
   the bootstrap/healthcheck plays).
3. Confirm `99-healthcheck.yml`'s "Wait for each proxied site to respond"
   task passes for the new entry — that's also where a missing/misrouted
   DNS record would show up first, as a timeout rather than a Caddy error.

## Adding or changing a DNS entry that isn't Caddy-proxied

Edit `dns_hosts` in `inventory/group_vars/dns.yml` directly (e.g. `gw` —
anything not fronted by Caddy), re-run
`ansible-playbook playbooks/05-dns.yml`. Only `coredns`'s zone file
(`db.zone.j2`) renders from this list now — Pihole no longer holds its own
copy, it conditionally forwards to CoreDNS instead (see the `pihole` role
above) — so there's nothing else to update.

## Inventory

`ansible.cfg`'s `inventory` setting lists two sources explicitly (not a
directory — Ansible's directory-scan default `INVENTORY_IGNORE_EXTS`
includes `ini`, which would silently skip Terraform's own `hosts.ini`):

- `inventory/hosts.ini` — **generated by Terraform**, gitignored. `[caddy]`
  and `[dns]` groups, each with its VM's Terraform-assigned IP.
- `inventory/hosts_static.ini` — **hand-authored, never generated,
  committed**. Hosts Terraform doesn't manage — today just `pi3-01`
  (`[pi3]` group) — plus the `[pihole:children]` group (`dns` + `pi3`, no
  hosts of its own) used to target both Pihole instances together.

group_vars, all hand-authored and never overwritten:

- `inventory/group_vars/all.yml` — `caddy_base_dir`, `caddy_version`,
  `caddy_sites`, `letsencrypt_email`, `letsencrypt_dns_resolvers`,
  `cloudflare_api_token`, and the DNS zone-wide constants both CoreDNS and
  every Pihole instance need: `dns_zone`, `coredns_ip`,
  `coredns_secondary_ip`, `dns_forward_resolvers`.
- `inventory/group_vars/dns.yml` — scoped to `[dns]` (server01) only:
  `dns_base_dir`, the `dns_macvlan_*` network config, `coredns_version`,
  `dns_hosts`, and server01's own Pihole instance settings
  (`pihole_network_mode: macvlan`, `pihole_ip`, `pihole_base_dir`).
- `inventory/group_vars/pihole.yml` — scoped to `[pihole]` (dns + pi3, so
  both Pihole instances see it): `pihole_version`, `pihole_timezone`,
  `pihole_webpassword`, `pihole_revserver_subnet`. Single source of truth
  for what must be identical on both instances.
- `inventory/group_vars/pi3.yml` — scoped to `[pi3]` (pi3-01) only:
  `docker_preinstalled: false`, `pihole_network_mode: host`, `pihole_ip`,
  `pihole_base_dir`.

## Playbooks

- `00-bootstrap.yml` — `hosts: all`, runs `common` (installs Docker on
  pi3-01 first, since it's not a Packer-built host — see `common` above).
- `05-dns.yml` — two plays: `hosts: dns` runs `dns_network` -> `coredns`
  (server01 only — no macvlan or CoreDNS on the Pi); `hosts: pihole` runs
  `pihole` (both instances — dns + pi3).
- `10-caddy.yml` — `hosts: caddy`, runs `caddy`.
- `99-healthcheck.yml` — three plays. DNS play (`hosts: dns`): confirms
  both containers are `Running`, then `ansible.builtin.wait_for` port 53
  on `.2`/`.5`, **delegated to `localhost`** (the Ansible control
  machine) — Docker's macvlan driver can't be reached from its own Docker
  host by design, so this also happens to be the more meaningful test
  (same vantage point a real LAN client has). Pihole-secondary play
  (`hosts: pi3`): same shape, checks `.6` — host networking there, so the
  macvlan limitation doesn't apply, but delegating to `localhost` still
  matches the real-client vantage point. The QNAP-hosted CoreDNS secondary
  (`.3`) is deliberately **not** checked here — it's a device this repo
  doesn't manage or guarantee is reachable at every deploy. Caddy play
  (`hosts: caddy`): confirms the container is `Running`, then polls each
  `caddy_sites` fqdn over HTTPS until it returns a response
  (200/301/302/401/403 all count — the point is "Caddy answered with a
  valid cert and proxied somewhere," not asserting every backend's own
  auth state).
- `site.yml` — chains all four via `import_playbook`, in order (bootstrap
  -> dns -> caddy -> healthcheck). This is what
  `ansible-playbook playbooks/site.yml` actually runs.

## Secrets

`CLOUDFLARE_API_TOKEN` and `PIHOLE_WEBPASSWORD` come from `secrets.yaml`
(SOPS + age) via `ansible/.envrc`'s `source_up` + direnv chain — same
mechanism as every other tool in this pipeline. See `CLAUDE.md`'s
"Credentials & secrets" and the root `README.md`'s "Secrets management"
section for the full setup. Never put either directly in
`inventory/group_vars/`— the `lookup('env', ...)` indirection there is what
keeps the actual secret out of a file that's committed in plaintext YAML.

`letsencrypt_email` (the ACME account contact) is *not* routed through this
chain — it's not a credential, just a contact address, so it's a plain
value directly in `inventory/group_vars/all.yml` (same pattern as the
elastic repo's `inventory/group_vars/kibana.yml`). Edit it there directly
if you want a different address.
