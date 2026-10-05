# Ansible — Caddy + DNS configuration

Third stage of the pipeline: configures the VMs Terraform just cloned. Run
from `ansible/`, using the repo-root `.venv/`, which mise activates
automatically. `mise run setup:ansible` (part of `mise install`) installs
the pinned `ansible`/`ansible-lint` from `requirements.txt` and pulls
`community.docker` and `ansible.utils` from `requirements.yml`.

```bash
cd ansible
ansible-playbook playbooks/site.yml   # decrypts its *.sops.yaml secrets at task time
```

## Roles

- **`common`** — preflight checks (`asserts.yml`): confirms the host is
  Ubuntu >= 22.04, Docker + the Compose plugin (baked in by the Packer
  template) are present, and, for the
  `caddy`/`pihole` groups specifically, that `cloudflare_api_token`
  (`group_vars/caddy.sops.yaml`) and `pihole_webpassword`
  (`group_vars/pihole.sops.yaml`) resolved non-empty. Fails
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
     the recursive catch-all (`acl`, `health`,
     `prometheus`, `cache`, `forward`, `log`, `loadbalance`), with
     `forward` targets parametrized by `dns_forward_resolvers`.
     `health`/`prometheus` only live in the catch-all block (each opens
     its own listener; duplicating one across blocks fails to start).
     Plugin reference: <https://coredns.io/plugins/>.
  2. `templates/db.zone.j2` — an RFC1035 zone file (`$ORIGIN`, SOA with a
     Unix-timestamp serial, NS records for `ns1`/`ns2`, one A record per
     `dns_hosts` entry) — the single source of truth for the local zone.
  3. `templates/docker-compose.yml.j2` — pulls the pinned
     `coredns/coredns` image, mounts the Corefile + zone file, attaches to
     the external macvlan network at `coredns_ip` (`192.168.68.2`). No
     `HEALTHCHECK` — the official image is built `FROM scratch` (no
     shell/wget/curl to run one); see `99-healthcheck.yml` instead.

  No secrets involved — any change to the Corefile/zone file/compose file
  notifies the `Restart coredns` handler. The zone file's Unix-timestamp
  serial changes on every Ansible run by design, so this handler fires
  every run even when `dns_hosts` itself didn't change.
- **`pihole`** — applies to the `pihole` group (today just `dns`: the
  primary; the secondary on the QNAP is set up by hand from the same
  values, see [`PIHOLE-SECONDARY.md`](PIHOLE-SECONDARY.md)), renders and
  brings up Pihole, ad-blocking only:
  1. `templates/env.j2` — `FTLCONF_webserver_api_password` (from
     `pihole_webpassword`), `TZ`, `FTLCONF_dns_upstreams` (from
     `dns_forward_resolvers`, used for everything outside `dns_zone`),
     `FTLCONF_dns_revServers` (two `;`-joined entries, one per CoreDNS
     instance — `<enabled>,<cidr>,<server>#<port>,<domain>` — conditionally
     forwards `dns_zone` queries to CoreDNS instead of Pihole holding its
     own copy; format per <https://docs.pi-hole.net/ftldns/configfile/>), rendered
     to `.env` and loaded via `env_file:` — same secret-hygiene reasoning
     as Caddy's `CLOUDFLARE_API_TOKEN` (never templated straight into the
     compose file, so `docker inspect`/`docker compose config` can't leak
     it). `FTLCONF_dns_hosts` is deliberately **not** rendered —
     CoreDNS's zone file is the sole source of truth for local records;
     the accepted trade-off is that Pihole doesn't auto-answer PTR
     lookups for these hosts, and CoreDNS has no reverse zone either. Every
     var this template uses comes from `group_vars/all.yml` or
     `group_vars/pihole.yml`, never from the instance-specific
     `group_vars/dns.yml` — so the QNAP secondary can copy exactly the same
     values.
  2. `templates/docker-compose.yml.j2` — pulls the pinned `pihole/pihole`
     image, `cap_add: NET_ADMIN`, `/etc/pihole` on a named volume so
     Pihole's own state (once it accumulates any) survives a recreate.
     Attaches to the external macvlan network at `pihole_ip`
     (`192.168.68.5`, `group_vars/dns.yml`).

  Any change notifies the `Restart pihole` handler. The two instances share
  settings through `group_vars/pihole.yml` only — there's
  no gravity.db/blocklist replication (gravity-sync, Teleporter, etc.) —
  both instances start from Pi-hole's shipped defaults and every other
  setting is already identical, so a sync mechanism isn't worth the extra
  moving parts.
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
     reaches the running config — an upstream Caddy limitation,
     `caddyserver/caddy` issues #4008/#7192; Caddy's admin API config dump
     shows whether `resolvers` landed). `resolvers` matters because the `proxy` VM's own
     system resolver is CoreDNS, which is authoritative for
     `homelab.bcochofel.com`, so without it Caddy's ACME zone-cut
     discovery gets fooled into stopping at `homelab.bcochofel.com`
     instead of walking up to the real Cloudflare zone `bcochofel.com`,
     failing with `"expected 1 zone, got 0 for homelab.bcochofel.com"`.
     The explicit `issuer acme` also drops Caddy's default ZeroSSL
     fallback issuer (Let's Encrypt is the only issuer), followed
     by a plain `reverse_proxy` directive, with a `transport http { ... }`
     block added only when a site needs one:
     - `insecure_skip_verify: true` — upstream presents a self-signed cert
       on the LAN hop (e.g. the QNAP admin UI); doesn't weaken the
       public-facing TLS Caddy itself terminates.
     - `upstream_sni: <hostname>` — upstream is addressed by IP but
       presents a cert issued for its own hostname (e.g. a backend that
       terminates its own Let's Encrypt cert for its fqdn — without
       `tls_server_name` set to that hostname, Caddy's default TLS
       verification checks the cert against the IP instead and fails).
       This is TLS bridging — two independent TLS sessions
       (client<->Caddy, Caddy<->backend), not a conflict.
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
  unconditionally every play (see the task comment for why: handler-driven
  rebuilds race `community.docker.docker_compose_v2`'s idempotency check
  against stale image references once old builds are garbage-collected;
  BuildKit's cache makes a no-op rebuild cheap anyway). That covers Dockerfile changes
  (image digest changes, `up` recreates the container) and
  docker-compose.yml changes (service definition changes, `up` recreates
  it) — but **not** Caddyfile or `.env` content changes: both are
  bind-mounted, not baked into the image, and `up` only diffs the service
  *definition*, never a bind-mounted file's *contents*. A separate task
  explicitly runs `docker compose restart caddy` when the Caddyfile/`.env`
  render tasks report `changed`, to actually pick up content-only changes
  (without it, Caddy keeps serving its old in-memory config).

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
(`db.zone.j2`) renders from this list — Pihole holds no copy of its own,
it conditionally forwards to CoreDNS (see the `pihole` role above) — so
there's nothing else to update.

## Inventory

`ansible.cfg`'s `inventory` setting names the file explicitly (not the
directory — Ansible's directory-scan default `INVENTORY_IGNORE_EXTS`
includes `ini`, which would silently skip it):

- `inventory/hosts.ini` — **generated by Terraform**, gitignored. `[caddy]`
  and `[dns]` groups, each with its VM's Terraform-assigned IP, plus
  `[pihole:children]` (`dns`): every host running a Pihole this repo
  deploys.

group_vars, all hand-authored and never overwritten:

- `inventory/group_vars/all.yml` — `caddy_base_dir`, `caddy_version`,
  `caddy_sites`, `letsencrypt_email`, `letsencrypt_dns_resolvers`, and
  the DNS zone-wide constants CoreDNS and Pihole share (and the QNAP
  secondaries copy): `dns_zone`, `coredns_ip`, `coredns_secondary_ip`,
  `dns_forward_resolvers`.
- `inventory/group_vars/dns.yml` — scoped to `[dns]` (server01) only:
  `dns_base_dir`, the `dns_macvlan_*` network config, `coredns_version`,
  `dns_hosts`, and server01's own Pihole instance settings (`pihole_ip`,
  `pihole_base_dir`).
- `inventory/group_vars/pihole.yml` — scoped to `[pihole]`:
  `pihole_version`, `pihole_timezone`, `pihole_revserver_subnet`, and
  `pihole_webpassword` (from `pihole.sops.yaml`). Single source of truth
  for the settings the QNAP secondary mirrors.

## Playbooks

- `00-bootstrap.yml` — `hosts: all`, runs `common`.
- `05-dns.yml` — two plays: `hosts: dns` runs `dns_network` -> `coredns`;
  `hosts: pihole` runs `pihole`.
- `10-caddy.yml` — `hosts: caddy`, runs `caddy`.
- `99-healthcheck.yml` — separates what this repo deploys from external
  dependencies. A failure in the first **stops the playbook**; a failure
  in the second is **reported only** (the task shows as failed, then
  ignored) and listed again in a summary at the end.
  - DNS play (`hosts: dns`): confirms both containers are `Running`, then
    `ansible.builtin.wait_for` port 53 on `.2`/`.5`, **delegated to
    `localhost`** (the Ansible control machine) — Docker's macvlan driver
    can't be reached from its own Docker host by design, so this is also
    the more meaningful test (same vantage point a real LAN client has).
    External: the QNAP secondaries (CoreDNS `.3`, Pihole `.6`) on port 53.
  - Caddy play (`hosts: caddy`): confirms the container is `Running`,
    then requests each `caddy_sites` fqdn over HTTPS, without following
    redirects, retrying while the answer is status `-1` (no valid TLS
    answer yet, e.g. ACME still issuing on a fresh VM). Still `-1` after
    the retries is Caddy's failure and stops the playbook. Any HTTP
    status means Caddy works; the backend counts as ready on
    200/301/302/401/403. Anything else (502/504 from Caddy when the
    backend is down, or the backend's own error) is an external issue.
  - Summary play: prints every external issue collected above, or "All
    external dependencies are ready.".
- `site.yml` — chains all four via `import_playbook`, in order (bootstrap
  -> dns -> caddy -> healthcheck). This is what
  `ansible-playbook playbooks/site.yml` actually runs.

## Secrets

Each secret lives in the SOPS-encrypted, committed `group_vars` file of the
only group that needs it, so no other host ever sees it:

- `inventory/group_vars/caddy.sops.yaml` — `cloudflare_api_token`
  (Caddy's DNS-01 ACME).
- `inventory/group_vars/pihole.sops.yaml` — `pihole_webpassword`.

The `community.sops` vars plugin (`ansible.cfg`:
`vars_plugins_enabled = host_group_vars,community.sops.sops`) decrypts them
with your age key at task time (`[community.sops] vars_stage = task`), so
`ansible-lint`, `--syntax-check` and `ansible-inventory` never decrypt
them, and `ansible-playbook` needs no wrapper. Keep `host_group_vars` in
that list: the setting replaces Ansible's default list, and without it
plain `group_vars` files stop loading.

See [`CREDENTIALS.md`](CREDENTIALS.md). Never put a secret in a plain
(unencrypted) `group_vars` file.

`letsencrypt_email` (the ACME account contact) is *not* routed through this
chain — it's not a credential, just a contact address, so it's a plain
value directly in `inventory/group_vars/all.yml`. Edit it there directly
if you want a different address.
