# Packer — Ubuntu 26.04 + Docker + Elastic Agent template

Minimal cloud-init-ready Ubuntu 26.04 template with Docker + Compose plugin
baked in, plus Elastic Agent installed but not enrolled and its service
disabled (ADR-3) — both VMs in this repo (`proxy`/Caddy and `dns`/CoreDNS+Pihole)
clone from this same template. Deliberately stripped down: no proxy
support, no custom CA import, no
security-scanning tooling (AIDE, rkhunter, chkrootkit, lynis, auditd) and no
in-VM vulnerability scanning (Trivy). SSH hardening and unattended-upgrades
are configured via autoinstall. No workload-specific host tuning — Caddy, CoreDNS and Pihole need none.

## Build

```bash
cd packer/ubuntu-26.04
mise run packer:build   # packer init + build; credentials: docs/CREDENTIALS.md
```

Provisioning runs three scripts in order, then seals the template:
`scripts/15-fix-initrd-network.sh` (no networking in the initrd — see
ADR-2), `scripts/20-install-docker.sh` (Docker CE + Compose) and
`scripts/30-install-elastic-agent.sh` (Elastic Agent, not enrolled,
service disabled — see ADR-3).
`scripts/99-cleanup-seal.sh` runs last and seals the template.

Proxmox user/token setup is shared with the rest of this pipeline — see
[`../../docs/PACKER.md`](../../docs/PACKER.md). If a build fails, see
["Troubleshooting a failed build"](../../docs/PACKER.md#troubleshooting-a-failed-build)
in that same doc for how to keep the VM alive and pull `cloud-init` logs
instead of guessing.

## What it builds

A `proxmox-iso` source boots an Ubuntu 26.04 Server ISO, autoinstalls via
cloud-init (`http/user-data.yml.tpl` + `http/meta-data.yml` served over the
Packer HTTP server), then the initrd is stripped of networking, Docker is
installed and Elastic Agent is installed but left disabled — before the image is sealed and converted to a Proxmox template.
Terraform later clones this template for both the `proxy` and `dns` VMs
(see `docs/TERRAFORM.md`).

```text
ISO boot --autoinstall--> cloud-init (users, disk layout, packages,
  sysctl/limits, SSH hardening)
    --provisioners--> initrd network fix --> Docker install
                      --> Elastic Agent install (not enrolled, disabled)
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
| `scripts/15-fix-initrd-network.sh` | Omits dracut's network modules so nothing DHCPs the NIC before cloud-init's netplan config runs (see ADR-2) |
| `scripts/20-install-docker.sh` | Docker CE + Compose plugin, qemu-guest-agent |
| `scripts/30-install-elastic-agent.sh` | Elastic Agent from Elastic's signed tarball via `elastic-agent install` (Fleet-upgradable), not enrolled, service disabled and stopped (see ADR-3) |
| `scripts/99-cleanup-seal.sh` | Strips machine-id/SSH host keys/logs/cloud-init state and the build VM's static network (see ADR-4) before conversion to template |

## Decisions (ADRs)

### ADR-1: Provisioning scripts are numbered and ordered, not roles

Packer has no equivalent of Ansible roles/handlers, so provisioner ordering
*is* the dependency graph — Docker installs first, `99-cleanup-seal.sh` runs
last since it truncates logs and clears `/var/lib/cloud`. The `NN-` prefixes
exist purely to make that order legible in a directory listing, and to leave
room to slot a script back in between (e.g. `1N-*` for something that must
run before Docker) without renumbering everything else.

### ADR-2: No networking in the initrd (interface-rename race)

**Context.** Without this, every VM cloned from the template comes up
reachable, but on the *wrong* IP — DHCP-assigned instead of the static IP
Terraform's cloud-init `ipconfig0` configures. `cloud-init status --long` on
such a clone shows `extended_status: degraded done` with:
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

### ADR-3: Elastic Agent baked in, not enrolled, service disabled

**Context.** Both VMs will be monitored by a Fleet-managed Elastic Agent
once an Elastic stack exists (`homelab-proxmox-workloads`). Installing the
agent in the template means every clone already has it; enrolling it there
would bake one Fleet identity into every clone, and there's nothing to
enroll into yet.

**Decision.** `scripts/30-install-elastic-agent.sh` downloads Elastic's
**Linux tarball** at the exact `elastic_agent_version`, verifies its GPG
signature (signing key checked by fingerprint) and SHA-512, and runs
`elastic-agent install --non-interactive` without `--url`: the agent lands
in `/opt/Elastic/Agent` with an `elastic-agent.service` unit and briefly
starts standalone. The script then disables and stops the service. The
build fails if the service is still enabled or running, or if the
installed binary isn't the pinned version.

**Consequences.**

- Clones boot with the agent inert. A later Ansible playbook enrolls each
  host (`elastic-agent enroll` on the installed agent) and enables the
  service.
- **Fleet manages upgrades** (a tarball install running as a service is
  Fleet-upgradable; a DEB isn't). `elastic_agent_version` only sets the
  version a fresh clone starts at; after enrollment the running version
  follows Fleet, outside this repo's pins. Bump it now and then so new
  clones don't start far behind.
- No APT repo or package: unattended-upgrades and `apt upgrade` never touch
  the agent, and removal is `elastic-agent uninstall`, not `apt remove`.
- The agent's version must not be newer than the Elastic stack it enrolls
  into.

### ADR-4: The build VM uses a static IP, not DHCP

**Context.** The installer needs an address before it can do anything: it
fetches its autoinstall config (`user-data`) over HTTP from Packer on the
workstation, and Packer then connects over SSH. Both depended on the LAN
router's DHCP, so a build could only work while the router handed out a
lease.

**Decision.** The build VM gets a fixed address, `build_ip_cidr`
(`192.168.71.1/22` by default), with `build_gateway` and public
`build_nameservers` (`1.1.1.1`/`8.8.8.8`):

- The boot command adds the kernel parameter
  `ip=<ip>::<gateway>:<netmask>:<hostname>:ens18:none:<dns0>:<dns1>`, so
  the installer's NIC is up before `user-data` is fetched. It goes before
  `---`: parameters after `---` are copied into the installed system's
  kernel command line.
- `user-data`'s `network` section sets the same static address, which the
  installer keeps and writes into the installed system for the rest of
  the build.
- Packer connects to `ssh_host = <build IP>` rather than an address
  discovered through the guest agent.
- The nameservers are public so a build never depends on the homelab's own
  DNS, which may be what's being rebuilt.

**Consequences.**

- The build IP must be free and outside the router's DHCP pool. The pool
  is `192.168.68.50`–`192.168.70.250` and the fixed addresses below `.50`
  are crowded, so `192.168.71.0/24`, still inside the `/22`, is the range
  for Packer build VMs: one address per template, so builds of different
  templates can run at once. This template has `192.168.71.1`; the next
  template takes the next free address. Nothing else may use the range.
- The static network must not reach the clones: a `network:` key in
  `/etc/cloud/cloud.cfg.d/` takes precedence over the datasource, so it
  would beat the address Terraform sets through Proxmox's cloud-init, and
  every clone would come up on the build IP. `scripts/99-cleanup-seal.sh`
  removes the installer's network files from `/etc/cloud/cloud.cfg.d/` and
  `/etc/netplan/` (cloud-init renders a clone's netplan from the
  datasource on first boot), and fails the build if any `network:` key, or
  the build IP itself, is still under `/etc/netplan`, `/etc/cloud`,
  `/etc/systemd/network` or `/etc/default`.
- Building on another network means changing the three `build_*`
  defaults in `variables.pkr.hcl`.
- The typed boot command is longer, and the Proxmox plugin types each key
  as a separate API call, so at its default pace keys were dropped
  (`192.168.71.1` arrived as `192.71.1`). `boot_key_interval = "100ms"`
  slows the typing to about 15 seconds.

## Variables reference

Required (no default — set as `PKR_VAR_*` env):

| Variable | Source in this repo |
| --- | --- |
| `proxmox_api_url`, `proxmox_api_token_id`, `proxmox_api_token_secret`, `proxmox_node`, `proxmox_skip_tls_verify` | `PKR_VAR_*`, from `~/.secrets/homelab.yaml`, passed by `mise run packer:build` ([`docs/CREDENTIALS.md`](../../docs/CREDENTIALS.md)) |
| `password_hash` | `PKR_VAR_password_hash` in `~/.secrets/homelab.yaml` — generate with `mkpasswd -m sha-512 '<password>'` |

Everything else (VM sizing, packages, timezone, NTP, the build VM's static
network `build_ip_cidr`/`build_gateway`/`build_nameservers` (ADR-4),
`ssh_private_key_file`, `ssh_authorized_keys`, `additional_users`,
`install_docker`, `install_elastic_agent`, `elastic_agent_version`, …) has
a default in `variables.pkr.hcl`: change a value by changing its default
([`docs/PACKER.md`](../../docs/PACKER.md#configuration-defaults-and-secrets)).

## Known coupling to watch

- `username` here must match the `ansible_user` Terraform writes into the
  generated inventory, since Ansible connects as that user.
- `boot_iso_file` points at a specific Ubuntu ISO filename already uploaded
  to the Proxmox node's ISO storage — it is not fetched by Packer.
