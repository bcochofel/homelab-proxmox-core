# External dependencies

Services this repo relies on but doesn't deploy. You set each one up by
hand, once, from the steps below. `ansible/playbooks/99-healthcheck.yml`
checks them on every run: a dependency that isn't ready is reported (the
task shows as failed, then ignored) and listed in a summary at the end,
but never stops the playbook.

| Dependency | Where | Address | Used for | Setup |
| --- | --- | --- | --- | --- |
| CoreDNS secondary (`ns2`) | QNAP Container Station | `192.168.68.3` | Second authoritative server for `homelab.bcochofel.com` | [CoreDNS secondary](#coredns-secondary) |
| Pi-hole secondary (`pihole2`) | QNAP Container Station | `192.168.68.6` | Second ad-blocking resolver handed out by DHCP | [Pi-hole secondary](#pi-hole-secondary) |
| Home Assistant | Raspberry Pi 3 | `192.168.68.11:8123` | Backend of `ha.homelab.bcochofel.com` | [Home Assistant](#home-assistant) |
| QTS admin UI, Web Station | QNAP | `192.168.68.10` | Backends of `nas` and `www` | Nothing to configure |
| Proxmox VE web UI | Proxmox | `192.168.68.20:8006` | Backend of `pve1` | Nothing to configure |

Keep the fixed addresses out of the router's DHCP pool, or reserve them
on the router, so no other device is handed one while its host is off.

## QNAP: before either secondary

Both secondaries run as Container Station applications, each with its own
LAN IP through QNAP's `qnet` network driver (QNAP's equivalent of
macvlan, which also lets the NAS itself reach the containers). The NAS's
own port 53 isn't involved, so no port mappings are needed.

### Find the NAS network interface

The `qnet` driver needs the name of the interface on the LAN. SSH into
the NAS (enable it under *Control Panel → Network & File Services →
Telnet / SSH*), then:

```bash
ifconfig | grep -B1 'inet addr:192.168.68.10'
```

The line above the address starts with the interface name. On the
TS-230 it's `br0` (the bridge Container Station uses); use whatever yours
shows in both applications below.

### Use the real shared-folder paths

Create the folders under `/share/Container/` and use that **real path**
in the compose files — not `/Container/...` (the File Station shortcut).
Docker creates a missing bind-mount source instead of failing, so the
shortcut path silently mounts an empty directory: CoreDNS starts with no
Corefile, and Pi-hole loses its settings on every recreate.

## CoreDNS secondary

The authoritative **secondary** for `homelab.bcochofel.com` (`ns2`,
`192.168.68.3`). It mirrors the primary (`ns1`, `192.168.68.2`, on
`server01`) in two jobs:

- **Secondary for the local zone:** pulls `homelab.bcochofel.com` from
  `ns1` by zone transfer (AXFR). `ns1` notifies it on every change, so it
  stays in sync without polling.
- **Full resolver:** forwards every other name to `1.1.1.1`/`8.8.8.8`, so
  clients and the Pi-holes can use it if `ns1` is down, and devices can
  use it directly to bypass Pi-hole.

The primary's Corefile (`ansible/roles/coredns/templates/Corefile.j2`)
already allows the transfer and sends NOTIFY to `192.168.68.3`
(`transfer { to 192.168.68.3 }`, from `coredns_secondary_ip` in
`ansible/inventory/group_vars/all.yml`). Nothing changes on the primary
side: the secondary only needs to run at that address.

### 1. Create the Corefile

Create `/share/Container/coredns` on the NAS and save this as
`/share/Container/coredns/Corefile`:

```text
homelab.bcochofel.com:53 {
    errors
    acl {
        allow net 192.168.68.0/22
        block
    }
    secondary {
        transfer from 192.168.68.2
    }
    log
}

.:53 {
    errors
    acl {
        allow net 192.168.68.0/22
        block
    }
    health {
        lameduck 5s
    }
    prometheus :9153
    cache {
        success 9984 30
        denial 9984 5
    }
    forward . 1.1.1.1 8.8.8.8 {
        max_concurrent 1000
        health_check 5s
    }
    log
    loadbalance round_robin
}
```

The `.:53` block is the same as the primary's catch-all. Keep the two in
step: if `dns_forward_resolvers` or the ACL subnet changes in
`ansible/inventory/group_vars/`, change them here too.

### 2. Create the CoreDNS application

*Container Station → Applications → Create*, name it `coredns`, and paste:

```yaml
services:
  coredns:
    image: coredns/coredns:1.14.6   # same tag as coredns_version in group_vars/dns.yml
    container_name: coredns-secondary
    command: -conf /etc/coredns/Corefile
    networks:
      qnet-network:
        ipv4_address: 192.168.68.3
    volumes:
      - /share/Container/coredns:/etc/coredns
    restart: unless-stopped

networks:
  qnet-network:
    driver_opts:
      iface: br0                    # the NAS interface
    driver: qnet
    ipam:
      driver: qnet
      options:
        iface: br0                  # same interface again
      config:
        - subnet: 192.168.68.0/22
          gateway: 192.168.68.1
```

The image is built `FROM scratch` (no shell), so there's no healthcheck;
the checks below are the test.

### 3. Check CoreDNS

```bash
# On the NAS: the zone transferred
docker logs coredns-secondary 2>&1 | grep -i transferred
#   expect: plugin/file: Transferred: homelab.bcochofel.com. from 192.168.68.2:53

# From a LAN machine: same serial as the primary...
dig @192.168.68.2 homelab.bcochofel.com SOA +short
dig @192.168.68.3 homelab.bcochofel.com SOA +short

# ...authoritative local answers ("aa" flag)...
dig @192.168.68.3 nas.homelab.bcochofel.com

# ...and forwarding for everything else
dig @192.168.68.3 example.com +short
```

### CoreDNS operating notes

- **Restarts refetch the zone.** The `secondary` plugin keeps the zone in
  memory only, so every container restart pulls it again from `ns1`. If
  `ns1` is down at that moment, `ns2` has no local zone (internet names
  still resolve) and retries the transfer every 10 seconds until `ns1` is
  back.
- **Upgrades:** bump the image tag here whenever `coredns_version` changes
  in `ansible/inventory/group_vars/dns.yml`, then recreate the
  application.
- **Changing records:** never edit anything on the NAS for that. Change
  `dns_hosts` in `ansible/inventory/group_vars/dns.yml` and run the
  playbook; `ns1` sends NOTIFY and `ns2` pulls the new zone.

## Pi-hole secondary

The **secondary** Pi-hole (`pihole2`, `192.168.68.6`). It mirrors the
primary (`pihole`, `192.168.68.5`, on `server01`):

- **Ad-blocking resolver** for LAN clients: DHCP hands out both Pi-holes,
  so clients keep resolving, and blocking, if either one is down.
- **Conditional forwarding** of `homelab.bcochofel.com` to both CoreDNS
  instances (`192.168.68.2` and `192.168.68.3`); it holds no local
  records itself.
- **Every other name** goes to `1.1.1.1`/`8.8.8.8`.

The primary's settings come from `ansible/inventory/group_vars/pihole.yml`
and the zone-wide values in `ansible/inventory/group_vars/all.yml`. The
secondary uses the **same values**, copied by hand:

| Setting | Value | Source in this repo |
| --- | --- | --- |
| Image tag | `pihole/pihole:2026.07.2` | `pihole_version` (`pihole.yml`) |
| `TZ` | `Europe/Lisbon` | `pihole_timezone` (`pihole.yml`) |
| `FTLCONF_dns_upstreams` | `1.1.1.1;8.8.8.8` | `dns_forward_resolvers` (`all.yml`) |
| `FTLCONF_dns_revServers` | one entry per CoreDNS, see step 1 | `pihole_revserver_subnet` (`pihole.yml`), `coredns_ip`, `coredns_secondary_ip`, `dns_zone` (`all.yml`) |

Ad lists and the gravity database aren't copied between the two: each
starts from Pi-hole's defaults. Add a list on both if you add one.

### 1. Create the Pi-hole application

Create `/share/Container/pihole` on the NAS. Then *Container Station →
Applications → Create*, name it `pihole`, and paste:

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
      iface: br0                    # the NAS interface
    driver: qnet
    ipam:
      driver: qnet
      options:
        iface: br0                  # same interface again
      config:
        - subnet: 192.168.68.0/22
          gateway: 192.168.68.1
```

The container serves DNS (53) and the web UI (80/443) on its own address.

`FTLCONF_dns_revServers` holds two entries, `;`-separated, one per
CoreDNS instance. Each is `<enabled>,<client subnet>,<server>#<port>,<domain>`.

### 2. Set the web password

The password isn't in the compose file, so it never sits in plain text
on the NAS. Set it once the container is running:

```bash
# On the NAS
docker exec -it pihole-secondary pihole setpassword
```

It's stored hashed in `/etc/pihole`, on the bind mount, so it survives
recreating the application. Using the same password as the primary
(`pihole_webpassword`) gives you one login for both.

### 3. Check Pi-hole

```bash
# From a LAN machine: local names come from CoreDNS (Caddy's IP)...
dig @192.168.68.6 nas.homelab.bcochofel.com +short    # 192.168.68.16

# ...other names resolve...
dig @192.168.68.6 example.com +short

# ...and ads are blocked
dig @192.168.68.6 doubleclick.net +short              # 0.0.0.0
```

Then open <http://192.168.68.6/admin> and sign in with the password from
step 2.

### Pi-hole operating notes

- **Upgrades:** bump the image tag here whenever `pihole_version` changes
  in `ansible/inventory/group_vars/pihole.yml`, then recreate the
  application.
- **Changing settings:** change the value in `group_vars/` first (the
  primary picks it up on the next playbook run), then the matching line
  here, then recreate the application. The table above lists what to
  keep in step.
- **Changing records:** never on a Pi-hole. Change `dns_hosts` in
  `ansible/inventory/group_vars/dns.yml` and run the playbook; both
  Pi-holes forward the zone to CoreDNS.

## Home Assistant

Home Assistant runs on the Raspberry Pi 3 at `192.168.68.11`. Caddy
publishes it as `https://ha.homelab.bcochofel.com` (the `caddy_sites`
entry in `ansible/inventory/group_vars/all.yml`); the DNS record points
at Caddy (`192.168.68.16`), not at the Pi.

### 1. Give the Pi a fixed address

Set `192.168.68.11` as a static IP on the Pi, or reserve it for the Pi's
MAC address on the router. Either way, keep it out of the DHCP pool.

### 2. Trust Caddy as a reverse proxy

Home Assistant rejects proxied requests (HTTP 400) unless it trusts the
proxy. Add this to its `configuration.yaml` and restart Home Assistant:

```yaml
http:
  use_x_forwarded_for: true
  trusted_proxies:
    - 192.168.68.16     # Caddy (proxy VM)
```

Nothing else is needed on either side: Caddy handles the certificate,
and the WebSocket connection the frontend uses passes through it with
no extra configuration.

### 3. Check Home Assistant

```bash
# From a LAN machine: Home Assistant answers directly...
curl -sI http://192.168.68.11:8123 | head -1

# ...and through Caddy, with a valid certificate (200, not 400 or 502)
curl -sI https://ha.homelab.bcochofel.com | head -1
```

A 400 through Caddy means step 2 is missing; a 502 means Caddy can't
reach the Pi.
