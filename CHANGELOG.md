# 📦 Changelog

All notable changes to this infrastructure project will be documented here.

## [3.0.0](https://github.com/bcochofel/homelab-proxmox-core/compare/2.1.0...3.0.0) (2026-08-15)

### Bug Fixes

* **dns:** shorten dns_hosts comment lines past ansible-lint's 160-char limit ([f65921b](https://github.com/bcochofel/homelab-proxmox-core/commit/f65921b050a317a68c76473aa93fc14a8afed050))

### Features

* **dns:** CoreDNS primary/secondary, Pihole ad-blocking-only, VM re-IP ([555e37a](https://github.com/bcochofel/homelab-proxmox-core/commit/555e37a66681eb69003eb6209aa28e5e60bffced)), closes [4008/#7192](https://github.com/bcochofel/homelab-proxmox-core/issues/7192)

### BREAKING CHANGES

* **dns:** dns VM management IP moves .41 -> .15 and Proxmox
name changes dns -> server01; proxy VM management IP moves
.40 -> .16; CoreDNS/Pihole macvlan IPs move .42 -> .2 and .43 -> .5.
Requires destroying and recreating both VMs from a freshly-built
Packer template, and manually repointing router/DHCP DNS settings.

## [2.1.0](https://github.com/bcochofel/homelab-proxmox-core/compare/2.0.0...2.1.0) (2026-08-13)

### Features

* **dns:** add otel-demo and argocd records for k3s cluster ([53a8f02](https://github.com/bcochofel/homelab-proxmox-core/commit/53a8f0223aafbe041077f6ef99f380185b778560))

## [2.0.0](https://github.com/bcochofel/homelab-proxmox-core/compare/v1.6.0...2.0.0) (2026-08-13)

### Bug Fixes

* wrap caddy role's long changed_when to satisfy ansible-lint ([de12d37](https://github.com/bcochofel/homelab-proxmox-core/commit/de12d379ab8439d9f88bb32a3af1d01264945bd2))

### Features

* rewrite repo on bpg/proxmox with a dedicated Caddy + DNS pipeline ([d1c0606](https://github.com/bcochofel/homelab-proxmox-core/commit/d1c0606ab7988a8fb110470912dac5c97f91a880))

### BREAKING CHANGES

* Terraform state from the old core-components/Telmate
workspace is incompatible with the new bpg/proxmox core-caddy
workspace. The bind9 DNS LXC and dev_workstation Terraform module are
removed. Existing QNAP-hosted CoreDNS/Pihole containers must be
migrated to the new dns VM by hand (see README's "Migration cutover")
— nothing from the previous 1.x pipeline carries forward automatically.
