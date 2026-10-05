# Pi-hole secondary (QNAP Container Station)

The **secondary** Pi-hole (`pihole2`, `192.168.68.6`) runs as a Container
Station application on the QNAP TS-230, next to the CoreDNS secondary
([`COREDNS-SECONDARY.md`](COREDNS-SECONDARY.md)). It isn't managed by this
repo's Ansible: you set it up once by hand, using the files below.

It mirrors the primary (`pihole`, `192.168.68.5`, on `server01`):

- **Ad-blocking resolver** for LAN clients: DHCP hands out both Pi-holes,
  so clients keep resolving, and blocking, if either one is down.
- **Conditional forwarding** of `homelab.bcochofel.com` to both CoreDNS
  instances (`192.168.68.2` and `192.168.68.3`); it holds no local
  records itself.
- **Every other name** goes to `1.1.1.1`/`8.8.8.8`.

## How it fits with the primary

The primary's settings come from `ansible/inventory/group_vars/pihole.yml`
and the zone-wide values in `ansible/inventory/group_vars/all.yml`. The
secondary uses the **same values**, copied by hand into the application
below:

| Setting | Value | Source in this repo |
| --- | --- | --- |
| Image tag | `pihole/pihole:2026.07.2` | `pihole_version` (`pihole.yml`) |
| `TZ` | `Europe/Lisbon` | `pihole_timezone` (`pihole.yml`) |
| `FTLCONF_dns_upstreams` | `1.1.1.1;8.8.8.8` | `dns_forward_resolvers` (`all.yml`) |
| `FTLCONF_dns_revServers` | one entry per CoreDNS, see step 3 | `pihole_revserver_subnet` (`pihole.yml`), `coredns_ip`, `coredns_secondary_ip`, `dns_zone` (`all.yml`) |

Ad lists and the gravity database aren't copied between the two: each
starts from Pi-hole's defaults. Add a list on both if you add one.

## 1. Find the NAS network interface

Same as for the CoreDNS secondary: the container gets its own LAN IP
through QNAP's `qnet` driver, which needs the LAN interface name. On the
TS-230 it's `br0`; see
[`COREDNS-SECONDARY.md`](COREDNS-SECONDARY.md#1-find-the-nas-network-interface)
for how to check.

## 2. Create the data directory

Create the shared folder path on the NAS: `/share/Container/pihole`.

Use the **real path**, `/share/Container/pihole`, in the compose file —
not `/Container/pihole` (the File Station shortcut). Docker creates a
missing bind-mount source instead of failing, so the shortcut path
silently mounts an empty directory and Pi-hole loses its settings on
every recreate.

## 3. Create the Container Station application

*Container Station → Applications → Create*, name it `pihole`, and paste:

```yaml
services:
  pihole:
    image: pihole/pihole:2026.07.2   # same tag as pihole_version in group_vars/pihole.yml
    container_name: pihole-secondary
    environment:
      TZ: Europe/Lisbon
      FTLCONF_dns_upstreams: "1.1.1.1;8.8.8.8"
      FTLCONF_dns_revServers: "true,192.168.68.0/22,192.168.68.2#53,homelab.bcochofel.com;true,192.168.68.0/22,192.168.68.3#53,homelab.bcochofel.com"
    networks:
      qnet-network:
        ipv4_address: 192.168.68.6
    volumes:
      - /share/Container/pihole/etc-pihole:/etc/pihole
    restart: unless-stopped

networks:
  qnet-network:
    driver_opts:
      iface: br0                    # the interface from step 1
    driver: qnet
    ipam:
      driver: qnet
      options:
        iface: br0                  # same interface again
      config:
        - subnet: 192.168.68.0/22
          gateway: 192.168.68.1
```

No port mappings are needed: the container has its own address on the
LAN and serves DNS (53) and the web UI (80/443) there.

`FTLCONF_dns_revServers` holds two entries, `;`-separated, one per
CoreDNS instance. Each is `<enabled>,<client subnet>,<server>#<port>,<domain>`.

The web password isn't in the compose file, so it never sits in plain
text on the NAS. Set it once the container is running:

```bash
# On the NAS
docker exec -it pihole-secondary pihole setpassword
```

It's stored hashed in `/etc/pihole`, on the bind mount, so it survives
recreating the application. Using the same password as the primary
(`pihole_webpassword`) gives you one login for both.

## 4. Check it

```bash
# From a LAN machine: local names come from CoreDNS (Caddy's IP)...
dig @192.168.68.6 nas.homelab.bcochofel.com +short    # 192.168.68.16

# ...other names resolve...
dig @192.168.68.6 example.com +short

# ...and ads are blocked
dig @192.168.68.6 doubleclick.net +short              # 0.0.0.0
```

Then open <http://192.168.68.6/admin> and sign in with the password from
step 3.

## Operating notes

- **Upgrades:** bump the image tag here whenever `pihole_version` changes
  in `ansible/inventory/group_vars/pihole.yml`, then recreate the
  application.
- **Changing settings:** change the value in `group_vars/` first (the
  primary picks it up on the next playbook run), then the matching line
  here, then recreate the application. The table in
  [How it fits with the primary](#how-it-fits-with-the-primary) lists
  what to keep in step.
- **Changing records:** never on a Pi-hole. Change `dns_hosts` in
  `ansible/inventory/group_vars/dns.yml` and run the playbook; both
  Pi-holes forward the zone to CoreDNS.
