# Packer — Ubuntu 26.04 + Docker template

Minimal cloud-init-ready Ubuntu 26.04 template with Docker + Compose plugin
baked in — both VMs in this repo (`proxy`/Caddy and `dns`/CoreDNS+Pihole)
clone from this same template. Deliberately stripped down: no proxy
support, no custom CA import, no
security-scanning tooling (AIDE, rkhunter, chkrootkit, lynis, auditd) and no
in-VM vulnerability scanning (Trivy). SSH hardening and unattended-upgrades
are still configured via autoinstall — see ADR-2 below for why the rest was
cut. Adapted from the equivalent template in
the sibling `homelab-proxmox-elastic` repo, with the Elasticsearch-specific
host tuning (`vm.max_map_count`, memlock/nofile limits, `/opt/elastic` base
dir, pre-installed Elastic Agent) removed — Caddy needs none of that.

## Build

```bash
cp variables.pkrvars.hcl.example variables.auto.pkrvars.hcl   # fill in, gitignored, auto-loaded
make packer-init                 # non-mutating: packer init . (plugin download)
cd packer/ubuntu-26.04 && packer build .   # run directly from this directory
```

Provisioning runs two scripts in order, then seals the template:
`scripts/15-fix-initrd-network.sh` (no networking in the initrd — see
ADR-3) and `scripts/20-install-docker.sh` (Docker CE + Compose).
`scripts/99-cleanup-seal.sh` runs last and seals the template.

Proxmox user/token setup is shared with the rest of this pipeline — see
[`../../docs/PACKER.md`](../../docs/PACKER.md). If a build fails, see
["Troubleshooting a failed build"](../../docs/PACKER.md#troubleshooting-a-failed-build)
in that same doc for how to keep the VM alive and pull `cloud-init` logs
instead of guessing.

## What it builds

A `proxmox-iso` source boots an Ubuntu 26.04 Server ISO, autoinstalls via
cloud-init (`http/user-data.yml.tpl` + `http/meta-data.yml` served over the
Packer HTTP server), then the initrd is stripped of networking and Docker is
installed — before the image is sealed and converted to a Proxmox template.
Terraform later clones this template for both the `proxy` and `dns` VMs
(see `docs/TERRAFORM.md`).

```text
ISO boot --autoinstall--> cloud-init (users, disk layout, packages,
  sysctl/limits, SSH hardening)
    --provisioners--> initrd network fix --> Docker install
        --provisioners--> cleanup & seal
```

## File map

| File | Role |
| --- | --- |
| `ubuntu-26.04.pkr.hcl` | `source` (Proxmox connection, VM shape, boot) + `build` (provisioner order) |
| `variables.pkr.hcl` | Every input variable, grouped by concern |
| `locals.pkr.hcl` | Renders `http/user-data.yml.tpl` into `local.user_data` |
| `versions.pkr.hcl` | Packer core + `hashicorp/proxmox` plugin version pins |
| `http/user-data.yml.tpl` | cloud-init autoinstall: disk layout (LVM), users, SSH hardening |
| `http/meta-data.yml` | cloud-init meta-data (mostly empty; required by the datasource) |
| `scripts/15-fix-initrd-network.sh` | Omits dracut's network modules so nothing DHCPs the NIC before cloud-init's netplan config runs (see ADR-3) |
| `scripts/20-install-docker.sh` | Docker CE + Compose plugin, qemu-guest-agent |
| `scripts/99-cleanup-seal.sh` | Strips machine-id/SSH host keys/logs/cloud-init state before conversion to template |
| `variables.pkrvars.hcl.example` | Copy to `variables.auto.pkrvars.hcl` (gitignored, auto-loaded by Packer) and fill in |

## Decisions (ADRs)

### ADR-1: Provisioning scripts are numbered and ordered, not roles

Packer has no equivalent of Ansible roles/handlers, so provisioner ordering
*is* the dependency graph — Docker installs first, `99-cleanup-seal.sh` runs
last since it truncates logs and clears `/var/lib/cloud`. The `NN-` prefixes
exist purely to make that order legible in a directory listing, and to leave
room to slot a script back in between (e.g. `1N-*` for something that must
run before Docker) without renumbering everything else.

### ADR-2: No networking in the initrd (interface-rename race)

**Context.** The sibling `homelab-proxmox-elastic` repo's first real
`terraform apply` against this same template shape had every cloned VM come
up reachable, but on the *wrong* IP — DHCP-assigned instead of the static IP
Terraform's cloud-init `ipconfig0` configured. `cloud-init status --long` on
a clone showed `extended_status: degraded done` with:
`Unable to rename interfaces: [['<mac>', 'eth0', None, None]] due to
errors: ['[busy] Error renaming mac=<mac> from ens18 to eth0']`.

Root cause: Proxmox's auto-generated cloud-init network-config always names
the interface generically (`eth0`) regardless of the guest's real
predictable name (`ens18` here), so cloud-init's netplan renderer has to
rename `ens18` → `eth0` to satisfy that name before it can apply the static
address. That rename requires the interface to be down. But dracut's
default **hostonly** mode had bundled the full network module stack
(`40network`, `11systemd-networkd`, etc.) into the initrd — not because
this VM's boot path needs it (root is local LVM, no NFS root, no network
unlock), but because the *build machine* (which needs internet to install
packages) has an active NIC, and hostonly detection includes modules based
on the build host, not the target's actual boot requirements. That
initrd-stage `systemd-networkd` DHCPs `ens18` and brings it up within ~3
seconds of boot — long before `cloud-init-network.service` runs — so by the
time cloud-init tries the rename, the interface is already up and "busy,"
the rename fails, and the static config never applies.

**Decision.** `scripts/15-fix-initrd-network.sh` drops
`/etc/dracut.conf.d/99-omit-network.conf` (`omit_dracutmodules` for every
network-related dracut module) and regenerates the initramfs
(`dracut --force --regenerate-all`) before Docker install, plus masks
the `systemd-networkd` units directly inside the initrd as defense in depth.
With no networking at all in the initrd, cloud-init's netplan config is the
first thing to ever touch the NIC, so the rename always succeeds.

**Consequences.** `scripts/15-fix-initrd-network.sh` fails the build hard
(exits 1) if the regenerated initrd still contains the network module,
rather than silently shipping a template with the bug still latent — this
class of failure only shows up after a real `terraform apply`, so it's
worth catching at build time.

## Variables reference

Required (no default — set via `variables.auto.pkrvars.hcl` or `PKR_VAR_*`
env):

| Variable | Source in this repo |
| --- | --- |
| `proxmox_api_url`, `proxmox_api_token_id`, `proxmox_api_token_secret`, `proxmox_node`, `proxmox_skip_tls_verify` | `packer/.envrc` (`PKR_VAR_*`, decrypted from `secrets.yaml` via SOPS + direnv) |
| `password_hash` | `variables.auto.pkrvars.hcl` — generate with `mkpasswd -m sha-512 '<password>'` |
| `ssh_private_key_file` | `variables.auto.pkrvars.hcl` — must pair with a key in `ssh_authorized_keys` |

Everything else (VM sizing, packages, timezone, NTP, `install_docker`, …) has
a default in `variables.pkr.hcl` and only needs overriding in
`variables.auto.pkrvars.hcl` when it should differ from that default.

## Known coupling to watch

- `username` here must match the `ansible_user` Terraform writes into the
  generated inventory, since Ansible connects as that user.
- `boot_iso_file` points at a specific Ubuntu ISO filename already uploaded
  to the Proxmox node's ISO storage — it is not fetched by Packer.
