# TODO / Roadmap

The single place phase status lives. When a phase is done, check it off
here — no need to also edit `README.md` or `CLAUDE.md`; both point here
instead of duplicating status inline.

## Phase 0 — Refactor to the elastic-repo architecture

- [x] Rebuild the repo structure to mirror `homelab-proxmox-elastic`:
      `bpg/proxmox`, HCP Terraform (`core-caddy` workspace), SOPS+age
      secrets via direnv, Docker Compose service pattern, custom
      Checkov/Trivy Proxmox policies, semantic-release, CLAUDE.md/TODO.md/
      docs split.
- [x] Remove the old bind9 DNS LXC and dev-workstation Terraform
      modules/roles.
- [x] Generate a dedicated age key for this repo and fill in the real
      recipient in `.sops.yaml`.
- [x] Create `secrets.yaml` for real (`sops secrets.yaml`) with the Proxmox
      tokens, cloud-init password, a **new**, separately-scoped Cloudflare
      API token, and `pihole_webpassword`.

## Phase 1 — Green Caddy VM

- [x] Packer: `ubuntu-26.04` template builds cleanly (Docker, initrd
      network fix).
- [x] Terraform: `proxy` VM clones from the template, static IP
      `192.168.68.40`, inventory generated.
- [x] Ansible: `common` preflight passes, `caddy` role builds the
      `xcaddy`-compiled image and brings up the container.
- [x] `nas`, `www`, `pve1` in `caddy_sites` issue real Let's Encrypt certs
      via Cloudflare DNS-01 and proxy correctly; `99-healthcheck.yml`
      passes. `kibana` is excluded from this repo's own
      healthcheck (`caddy_sites`' `external: true` flag,
      `group_vars/all.yml`) since its backend lives in the separate
      `homelab-proxmox-elastic` repo — verify it separately once that
      stack is deployed.

## Phase 1.5 — Green DNS VM + migration cutover

- [x] Terraform: `dns` VM clones from the template, static IP
      `192.168.68.41`, inventory generated.
- [x] Ansible: `dns_network` creates the macvlan network, `coredns` and
      `pihole` roles bring up both containers on `.42`/`.43` (these IPs
      were later reallocated — see Phase 1.6 below).
- [x] Verify Pihole's env vars (`roles/pihole/templates/env.j2`) live.
      Caught a real bug in the process: the training-data
      assumption that `/etc/pihole/custom.list` still populates local DNS
      records doesn't hold for Pi-hole v6/FTL v6 — `dns.hosts` stays `[]`
      even with the file present and mounted (confirmed by reading
      `pihole-FTL`'s own `src/config/env.c`). Local records must be forced
      via `FTLCONF_dns_hosts` (a `;`/`\n`-delimited `CONF_JSON_STRING_ARRAY`,
      same rule as `FTLCONF_dns_upstreams`). Removed the dead
      `custom.list.j2`/volume mount, added `FTLCONF_dns_hosts` built from
      `dns_hosts`.
- [x] `dig @192.168.68.42 <fqdn>` and `dig @192.168.68.43 <fqdn>` both
      resolve every `dns_hosts` entry correctly (these IPs were later
      reallocated — see Phase 1.6 below); `99-healthcheck.yml`'s DNS checks
      pass.
- [x] Migration cutover: point router/DHCP DNS settings at `.42`/`.43`,
      confirm clients pick up the new servers, then stop and remove the
      CoreDNS/Pihole containers in QNAP Container Station (`.5`/`.6`
      retired).

## Phase 1.6 — CoreDNS primary/secondary, Pihole conditional forwarding, re-IP

- [x] Terraform: `proxy` VM re-IPs `.40` -> `192.168.68.16`; `dns` VM
      re-IPs `.41` -> `192.168.68.15` and renames to `server01` (Ansible
      inventory group stays `dns`). Confirmed live via Proxmox: `server01`
      = vmid 100, `proxy` = vmid 101 (both auto-assigned, `vmid` no longer
      hardcoded — see CLAUDE.md), IPs match.
- [x] `coredns` role: CoreDNS becomes authoritative primary for `dns_zone`
      (`homelab.bcochofel.com`) at `192.168.68.2` (moved from `.42`),
      two-server-block Corefile (`file`+`transfer`+`acl` for the zone,
      `forward`+`cache`+`health`+`prometheus`+`acl` for the catch-all),
      new `db.zone.j2` RFC1035 zone file replacing `hosts.local.j2`.
      Deployed cleanly (`ansible-playbook site.yml`, `failed=0`).
- [x] `pihole` role: Pihole moves to `192.168.68.5` (from `.43`), stops
      rendering `FTLCONF_dns_hosts`, conditionally forwards `dns_zone` to
      `192.168.68.2`/`.3` via `FTLCONF_dns_revServers`. Ad-blocking only —
      not yet the network's primary resolver (DHCP cutover is a later,
      separate step). Deployed cleanly.
- [x] Both CoreDNS server blocks restrict queries to `192.168.68.0/22` via
      the `acl` plugin (implemented; external-subnet refusal not yet
      independently `dig`-tested, see below).
- [x] `dns_hosts`: remove `haos.homelab.bcochofel.com` (Home Assistant OS
      retired), rename `ns1`/`ns2`/add `pihole` entries to match the new
      IPs/roles, rename `dns` entry to `server01`.
- [x] Additional SSH key for the `bcochofel` user baked into the rebuilt
      Packer template (`packer/ubuntu-26.04/variables.auto.pkrvars.hcl`).
- [x] Two real bugs hit and fixed during this rollout, unrelated to the
      DNS redesign itself but exposed by the from-scratch VM recreation:
      (1) `99-healthcheck.yml`'s retry loop never actually retried
      (`until: _sites.status is defined` was always true on attempt 1 —
      fixed to check the real status codes); (2) Caddy's DNS-01 ACME
      failed with `"expected 1 zone, got 0 for homelab.bcochofel.com"`
      since CoreDNS becoming authoritative fooled Caddy's zone-cut
      discovery — fixed with an explicit `tls { issuer acme { dns
      cloudflare ... \n resolvers ... } } }` block (the simpler `tls {
      dns ... }` shorthand silently drops `resolvers`, a real open Caddy
      bug — `caddyserver/caddy` #4008/#7192); found along the way that the
      `caddy` role's `docker compose up -d --build` never picks up
      Caddyfile/`.env` *content* changes (bind-mounted, not baked into the
      image) — fixed with an explicit restart-on-change task. See
      CLAUDE.md for full detail on all three.
- [x] QNAP Container Station: stand up a CoreDNS `secondary` container at
      its own dedicated LAN IP (`192.168.68.3`, via Container Station's
      `qnet` network driver — not Docker's macvlan driver), AXFR-pulling
      `dns_zone` from `.2`. Deployed via a Container Station Application
      (compose YAML with a `qnet-network` block templated on
      `${QNET_STATIC_IP}`/`${QNET_INTERFACE}`/`${QNET_SUBNET}`/
      `${QNET_GATEWAY}`, following the same pattern as their existing
      Pihole app template). Confirmed via container logs: `[INFO]
      plugin/file: Transferred: homelab.bcochofel.com. from
      192.168.68.2:53`. One real gotcha hit along the way: the bind-mount
      source `/Container/coredns` (a File Station/GUI shortcut) isn't the
      actual host path Docker needs — QNAP's real filesystem path is
      `/share/Container/coredns`; using the shortcut path made Docker
      silently bind-mount a fresh *empty* directory instead of erroring,
      since Docker auto-creates missing bind-mount sources rather than
      failing (external to this repo's Ansible, not written down anywhere
      else — worth remembering if this ever needs rebuilding). A second
      gotcha: the QNAP's Corefile initially had only the
      `homelab.bcochofel.com:53` block (secondary/AXFR), no catch-all
      `.:53` — correct for "secondary of the internal zone only," but
      once the router is meant to point at `.3` as a general resolver
      (see below), anything outside `homelab.bcochofel.com` got REFUSED.
      Fixed by adding a `.:53` block mirroring the primary's catch-all
      exactly (`acl`, `health`, `prometheus`, `cache`, `forward .
      1.1.1.1 8.8.8.8`, `log`, `loadbalance`).
- [x] `dig @192.168.68.2 homelab.bcochofel.com SOA` and `dig
      @192.168.68.3 homelab.bcochofel.com SOA` agree exactly — same
      serial (`1786808225`), same NS records (`ns1`/`ns2`). Confirms the
      AXFR pair is genuinely in sync, not just "logs said transferred
      once".
- [x] `dig @192.168.68.3 pve1.homelab.bcochofel.com` resolves correctly
      (`192.168.68.16`, proper `ns1`/`ns2` authority records) and `dig
      @192.168.68.3 www.google.com` resolves too (real answers via the
      catch-all `forward` block) — the QNAP secondary is now a fully
      working general-purpose resolver, not just an internal-zone
      secondary. Not yet independently tested: every other `dns_hosts`
      entry individually, and the ACL refusing a `dig` from outside
      `192.168.68.0/22` — both low-risk/likely-fine given everything else
      checks out, but unverified.
- [x] Point router/DHCP DNS settings at `.2`/`.3` (CoreDNS only for now —
      deliberately not `.5`/Pihole yet, that cutover is a separate later
      step per Pihole's own primary/secondary redundancy work above).

## Phase 2 — Hardening / follow-up

- [ ] Pihole primary/secondary redundancy: today's Pihole
      (`192.168.68.5`, ad-blocking only, see Phase 1.6) is meant to become
      the **primary**, with a **secondary** Pihole on a Raspberry Pi 3 for
      redundancy. Needs a sync mechanism to replicate gravity/blocklists/
      settings from primary to secondary — evaluate options (e.g.
      `gravity-sync`, Pi-hole's own Teleporter export/import) against
      current docs before picking one; not designed yet. Deferred — for
      now only CoreDNS has primary/secondary redundancy (Phase 1.6);
      Pihole stays a single instance until this is built.
- [ ] Decide whether the public `bcochofel.com` Cloudflare zone should also
      get real A/AAAA records for these fqdns (currently LAN-only via the
      new in-Proxmox CoreDNS/Pihole), or stay internal-only with DNS-01
      used purely for cert issuance.
- [ ] Consider access logging / rate limiting on the `nas`/`www`/`pve1`
      site blocks if any is ever exposed beyond the LAN — `pve1` in
      particular puts the Proxmox admin UI behind the same public-issuable
      -cert front door as everything else, worth revisiting once there's
      more operational experience.
- [ ] Revisit Caddy version pin (`caddy_version` in
      `inventory/group_vars/all.yml`) periodically — check
      <https://hub.docker.com/_/caddy> for the current stable tag. Same for
      `coredns_version`/`pihole_version` in `group_vars/dns.yml`.
- [x] Re-import or hand-recreate any Pihole blocklist/whitelist
      customizations that existed on the QNAP-hosted instance — the fresh
      start deliberately didn't migrate gravity/blocklist state. Confirmed
      no customizations existed on the QNAP-hosted instance, so there is
      nothing to re-import.
- [x] Public GitHub repo has a stale secret (`rndc.key`, from the
      pre-refactor bind9 module) in its git history, even though the file
      is gone from the working tree. Confirmed clean: no `rndc.key` in the
      full local history (115 commits, non-shallow) and GitHub's own
      secret-scanning alerts for the repo are empty.

See `CLAUDE.md` for the detailed technical notes and decisions behind each
of these (agent-facing context) — this file is just the status list.
