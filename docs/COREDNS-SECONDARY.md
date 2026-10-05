# CoreDNS secondary (QNAP Container Station)

The authoritative **secondary** for `homelab.bcochofel.com` (`ns2`,
`192.168.68.3`) runs as a Container Station application on the QNAP
TS-230. It isn't managed by this repo's Ansible: you set it up once by
hand, using the files below.

It does two jobs, mirroring the primary (`ns1`, `192.168.68.2`, on
`server01`):

- **Secondary for the local zone:** pulls `homelab.bcochofel.com` from
  `ns1` by zone transfer (AXFR). `ns1` notifies it on every change, so it
  stays in sync without polling.
- **Full resolver:** forwards every other name to `1.1.1.1`/`8.8.8.8`, so
  clients and the Pi-holes can use it if `ns1` is down, and devices can
  use it directly to bypass Pi-hole.

## How it fits with the primary

The primary's Corefile (`ansible/roles/coredns/templates/Corefile.j2`)
already allows the transfer and sends NOTIFY to `192.168.68.3`
(`transfer { to 192.168.68.3 }`, from `coredns_secondary_ip` in
`ansible/inventory/group_vars/all.yml`). Nothing changes on the primary
side to add the secondary: it only needs to run at that address.

## 1. Find the NAS network interface

The container gets its own LAN IP through QNAP's `qnet` network driver
(QNAP's equivalent of macvlan, which also lets the NAS itself reach the
container). The driver needs the name of the interface on the LAN.

SSH into the NAS (enable it under *Control Panel → Network & File
Services → Telnet / SSH*), then:

```bash
ifconfig | grep -B1 'inet addr:192.168.68.10'
```

The line above the address starts with the interface name. On the
TS-230 it's `br0` (the bridge Container Station uses); use whatever yours
shows.

## 2. Create the config directory and Corefile

Create the shared folder path on the NAS: `/share/Container/coredns`.

Use the **real path**, `/share/Container/coredns`, in the compose file —
not `/Container/coredns` (the File Station shortcut). Docker creates a
missing bind-mount source instead of failing, so the shortcut path
silently mounts an empty directory and CoreDNS starts with no Corefile.

Save this as `/share/Container/coredns/Corefile`:

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

## 3. Create the Container Station application

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
LAN and listens on port 53 there. The NAS's own port 53 isn't involved.

The image is built `FROM scratch` (no shell), so there's no healthcheck;
the checks below are the test.

## 4. Check it

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

## Operating notes

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
