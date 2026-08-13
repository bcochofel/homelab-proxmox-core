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

- [ ] Packer: `ubuntu-26.04` template builds cleanly (Docker, initrd
      network fix).
- [x] Terraform: `proxy` VM clones from the template, static IP
      `192.168.68.40`, inventory generated (2026-08-13).
- [x] Ansible: `common` preflight passes, `caddy` role builds the
      `xcaddy`-compiled image and brings up the container (2026-08-13).
- [x] `nas`, `www`, `pve1` in `caddy_sites` issue real Let's Encrypt certs
      via Cloudflare DNS-01 and proxy correctly; `99-healthcheck.yml`
      passes (2026-08-13). `kibana` is excluded from this repo's own
      healthcheck (`caddy_sites`' `external: true` flag,
      `group_vars/all.yml`) since its backend lives in the separate
      `homelab-proxmox-elastic` repo — verify it separately once that
      stack is deployed.

## Phase 1.5 — Green DNS VM + migration cutover

- [x] Terraform: `dns` VM clones from the template, static IP
      `192.168.68.41`, inventory generated (2026-08-13).
- [x] Ansible: `dns_network` creates the macvlan network, `coredns` and
      `pihole` roles bring up both containers on `.42`/`.43` (2026-08-13).
- [x] Verify Pihole's env vars (`roles/pihole/templates/env.j2`) live
      (2026-08-13). Caught a real bug in the process: the training-data
      assumption that `/etc/pihole/custom.list` still populates local DNS
      records doesn't hold for Pi-hole v6/FTL v6 — `dns.hosts` stays `[]`
      even with the file present and mounted (confirmed by reading
      `pihole-FTL`'s own `src/config/env.c`). Local records must be forced
      via `FTLCONF_dns_hosts` (a `;`/`\n`-delimited `CONF_JSON_STRING_ARRAY`,
      same rule as `FTLCONF_dns_upstreams`). Removed the dead
      `custom.list.j2`/volume mount, added `FTLCONF_dns_hosts` built from
      `dns_hosts`.
- [x] `dig @192.168.68.42 <fqdn>` and `dig @192.168.68.43 <fqdn>` both
      resolve every `dns_hosts` entry correctly; `99-healthcheck.yml`'s DNS
      checks pass (2026-08-13).
- [ ] Migration cutover: point router/DHCP DNS settings at `.42`/`.43`,
      confirm clients pick up the new servers, then stop and remove the
      CoreDNS/Pihole containers in QNAP Container Station (`.5`/`.6`
      retired).

## Phase 2 — Hardening / follow-up

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
- [ ] Re-import or hand-recreate any Pihole blocklist/whitelist
      customizations that existed on the QNAP-hosted instance — the fresh
      start deliberately didn't migrate gravity/blocklist state.
- [ ] Public GitHub repo has a stale secret (`rndc.key`, from the
      pre-refactor bind9 module) in its git history, even though the file
      is gone from the working tree. Low urgency (bind9 is fully retired,
      key is almost certainly dead) but worth purging via `git filter-repo`
      + force-push at some point, since the repo is public.

See `CLAUDE.md` for the detailed technical notes and decisions behind each
of these (agent-facing context) — this file is just the status list.
