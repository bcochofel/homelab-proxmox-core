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

- **`common`** — preflight checks only (`roles/common/tasks/asserts.yml`):
  confirms the host is Ubuntu >= 22.04, Docker + the Compose plugin are
  present (baked in by Packer — this role never installs them), and, for
  the `caddy`/`dns` groups specifically, that `cloudflare_api_token`/
  `pihole_webpassword` resolved non-empty from the environment. Fails
  loudly and early rather than letting the `caddy`/`pihole` roles' own
  preflights fail later with a less obvious error.
- **`dns_network`** — one task
  (`community.docker.docker_network`): creates the shared Docker macvlan
  network (`dns_macvlan_network` in `inventory/group_vars/dns.yml`) both
  `coredns` and `pihole` attach to, giving each its own real LAN IP so
  both independently answer on port 53. Applied first, before either
  compose project references the network as `external`.
- **`coredns`** — renders and brings up CoreDNS:
  1. `templates/Corefile.j2` — same shape as the pre-migration QNAP
     config (`hosts`, `health`, `prometheus`, `cache`, `forward`, `log`,
     `loadbalance`), with the `forward` targets parametrized by
     `dns_forward_resolvers`.
  2. `templates/hosts.local.j2` — one line per `dns_hosts` entry
     (`inventory/group_vars/dns.yml`) — the single source of truth for the
     local zone, also consumed by `pihole`'s `FTLCONF_dns_hosts`.
  3. `templates/docker-compose.yml.j2` — pulls the pinned
     `coredns/coredns` image, mounts the two files above, attaches to the
     external macvlan network at `coredns_ip` (`192.168.68.42`). No
     `HEALTHCHECK` — the official image is built `FROM scratch` (no
     shell/wget/curl to run one); see `99-healthcheck.yml` instead.

  No secrets involved — any change to the Corefile/hosts.local/compose
  file notifies the `Restart coredns` handler.
- **`pihole`** — renders and brings up Pihole:
  1. `templates/env.j2` — `FTLCONF_webserver_api_password` (from
     `pihole_webpassword`), `TZ`, `FTLCONF_dns_upstreams` (from
     `dns_forward_resolvers`), `FTLCONF_dns_hosts` (from the same
     `dns_hosts` list `coredns`'s `hosts.local` renders from — Pi-hole
     v6/FTL v6 never reads `/etc/pihole/custom.list` for local DNS
     records, so this is forced via env var, confirmed against
     `pihole-FTL`'s own `src/config/env.c`), rendered to `.env` and loaded
     via `env_file:` — same secret-hygiene reasoning as Caddy's
     `CLOUDFLARE_API_TOKEN` (never templated straight into the compose
     file, so `docker inspect`/`docker compose config` can't leak it).
  2. `templates/docker-compose.yml.j2` — pulls the pinned `pihole/pihole`
     image, `cap_add: NET_ADMIN`, attaches to the external macvlan network
     at `pihole_ip` (`192.168.68.43`), `/etc/pihole` on a named volume so
     Pihole's own state (once it accumulates any) survives a recreate.

  Any change notifies the `Restart pihole` handler.
- **`caddy`** — renders and brings up the reverse proxy:
  1. `templates/Dockerfile.j2` — multi-stage `xcaddy build --with
     github.com/caddy-dns/cloudflare` against the pinned `caddy_version`,
     so the final image can do Cloudflare DNS-01 ACME natively — no
     certbot, no systemd timer, no deploy-hook.
  2. `templates/Caddyfile.j2` — a global `acme_dns cloudflare
     {$CLOUDFLARE_API_TOKEN}` option (makes DNS-01 the default challenge
     for every site, so no per-site `tls {}` block is needed) followed by
     one site block per entry in `caddy_sites`
     (`inventory/group_vars/all.yml`), each a plain `reverse_proxy`
     directive, with a `transport http { ... }` block added only when a
     site needs one:
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

  Any change to the Dockerfile, Caddyfile, compose file, or `.env` notifies
  the `Rebuild and restart caddy` handler (`build: always` — forces a
  fresh `xcaddy` build, not just a container restart, since a Caddyfile-only
  change still needs the rebuilt image to pick it up through Caddy's config
  reload path cleanly).

## Adding or changing a proxied site

Edit `caddy_sites` in `inventory/group_vars/all.yml` — no role or template
change needed, the `Caddyfile.j2` loop picks up any new entry. Then:

1. Add a matching entry to `dns_hosts` in `inventory/group_vars/dns.yml`,
   pointed at Caddy's IP (`192.168.68.40`), not the backend — keeps the two
   lists in sync (nothing automates this).
2. Re-run `ansible-playbook playbooks/site.yml` (or just
   `ansible-playbook playbooks/05-dns.yml playbooks/10-caddy.yml` to skip
   the bootstrap/healthcheck plays).
3. Confirm `99-healthcheck.yml`'s "Wait for each proxied site to respond"
   task passes for the new entry — that's also where a missing/misrouted
   DNS record would show up first, as a timeout rather than a Caddy error.

## Adding or changing a DNS entry that isn't Caddy-proxied

Edit `dns_hosts` in `inventory/group_vars/dns.yml` directly (e.g. `gw`,
`haos` — anything not fronted by Caddy), re-run
`ansible-playbook playbooks/05-dns.yml`. Both `coredns`'s `hosts.local`
and `pihole`'s `FTLCONF_dns_hosts` render from this one list, so there's
nothing else to update.

## Inventory

- `inventory/hosts.ini` — **generated by Terraform**, gitignored. `[caddy]`
  and `[dns]` groups, each with its VM's Terraform-assigned IP.
- `inventory/group_vars/all.yml` — **hand-authored, never overwritten**.
  Holds `caddy_base_dir`, `caddy_version`, `caddy_sites`,
  `letsencrypt_email`, and `cloudflare_api_token`.
- `inventory/group_vars/dns.yml` — **hand-authored, never overwritten**.
  Holds `dns_base_dir`, the `dns_macvlan_*` network config,
  `coredns_version`/`coredns_ip`, `pihole_version`/`pihole_ip`/
  `pihole_timezone`, `dns_hosts`, `dns_forward_resolvers`, and
  `pihole_webpassword`.

## Playbooks

- `00-bootstrap.yml` — `hosts: all`, runs `common`.
- `05-dns.yml` — `hosts: dns`, runs `dns_network` -> `coredns` -> `pihole`,
  in that order (the network has to exist before either compose project
  references it).
- `10-caddy.yml` — `hosts: caddy`, runs `caddy`.
- `99-healthcheck.yml` — DNS play (`hosts: dns`): confirms both containers
  are `Running`, then `ansible.builtin.wait_for` port 53 on `.42`/`.43`,
  **delegated to `localhost`** (the Ansible control machine) — Docker's
  macvlan driver can't be reached from its own Docker host by design, so
  this also happens to be the more meaningful test (same vantage point a
  real LAN client has). Caddy play (`hosts: caddy`): confirms the
  container is `Running`, then polls each `caddy_sites` fqdn over HTTPS
  until it returns a response (200/301/302/401/403 all count — the point
  is "Caddy answered with a valid cert and proxied somewhere," not
  asserting every backend's own auth state).
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
