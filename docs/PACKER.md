# Packer

First stage of the Packer -> Terraform -> Ansible pipeline: builds the
Proxmox VM template that Terraform later clones.

`packer/ubuntu-26.04/` is the one template this repo builds — its own
`*.pkr.hcl`/`variables.pkr.hcl`/`variables.pkrvars.hcl.example` and a README
with build instructions and the full deep-dive (what it builds, file map,
ADRs, variables reference). This doc covers what's shared with any future
template that might be added under `packer/`.

## Shared setup

- `packer/.envrc` exports `PKR_VAR_proxmox_api_url`, `_api_token_id`,
  `_api_token_secret`, `_node`, `_skip_tls_verify` via direnv, decrypted from
  the repo-root `secrets.yaml` (SOPS + age).
- `make packer-init` runs `packer init .` (plugin download, non-mutating).
  `packer build` is not a Makefile target — run it directly from the
  template's own directory, so the one command that actually writes to
  Proxmox stays explicit rather than hidden behind a wrapper.

## Proxmox user & API token

Packer authenticates as its own Proxmox user/token, separate from the
Terraform token used elsewhere in this repo, so each tool's blast radius
matches what it actually needs. Current token id:
`packer@pve!packer-automation`.

Create the role, user, and token from the Proxmox shell (or Datacenter ->
Permissions in the UI). `pveum` is part of `pve-manager` — it only exists on
the Proxmox node itself, not on WSL2 or any client machine, so it can't be
installed or run locally. Run it one of these ways:

- **SSH into the node** (simplest, and this repo already assumes SSH access
  to it — see `terraform/providers.tf`'s `ssh` block): `ssh root@<pve-host>`,
  then paste the commands below; or non-interactively,
  `ssh root@<pve-host> 'pveum role add PackerRole -privs "..."'` (mind the
  quoting — the whole `pveum` command needs to survive as one argument to
  `ssh`).
- **Proxmox web UI -> Datacenter -> Permissions** (Roles / Users / API
  Tokens tabs) — no CLI at all, same end result as every `pveum` command
  below, point-and-click.
- **Web UI -> node -> `>_ Shell`** — an in-browser terminal on the node
  itself, if you'd rather not set up SSH.

```bash
# 1. Role scoped to what the proxmox-iso builder actually does:
#    create a VM, configure it, boot/monitor it, allocate disk space,
#    and convert the finished VM to a template.
pveum role add PackerRole -privs "VM.Allocate,VM.Audit,VM.Config.CDROM,VM.Config.CPU,\
VM.Config.Disk,VM.Config.HWType,VM.Config.Memory,VM.Config.Network,VM.Config.Options,\
VM.Console,VM.Monitor,VM.PowerMgmt,Datastore.AllocateSpace,Datastore.AllocateTemplate,\
Datastore.Audit,Sys.Modify,SDN.Use"

# 2. User for the role (no password needed; auth is via API token only)
pveum user add packer@pve --comment "Packer template builder"
pveum aclmod / -user packer@pve -role PackerRole

# 3. API token. --privsep 0 means the token inherits the user's ACL directly;
#    with --privsep 1 (default) you'd also need to ACL the token id itself.
pveum user token add packer@pve packer-automation --privsep 0
```

The last command prints the token secret once — it is not retrievable again.
Put `proxmox_api_token_id = "packer@pve!packer-automation"` and the printed
secret into `secrets.yaml` (SOPS-encrypted) so `packer/.envrc` can export them
as `PKR_VAR_proxmox_api_token_id` / `PKR_VAR_proxmox_api_token_secret`.

| Privilege | Why the builder needs it |
| --- | --- |
| `VM.Allocate` | Create the VM the ISO installs into |
| `VM.Audit` | Read VM config/state while polling build status |
| `VM.Config.CDROM` | Attach the boot ISO, unmount it post-install (`boot_iso.unmount`) |
| `VM.Config.CPU`, `VM.Config.Memory`, `VM.Config.Disk`, `VM.Config.HWType`, `VM.Config.Network` | Set cores/sockets/CPU type, memory, disks/SCSI controller, qemu-guest-agent flag, network adapter |
| `VM.Config.Options` | Set template description, tags |
| `VM.Console`, `VM.Monitor` | Send boot-command keystrokes and QEMU monitor commands during autoinstall |
| `VM.PowerMgmt` | Start/stop/reset the VM around the build |
| `Datastore.AllocateSpace` | Allocate the VM disk on `storage_pool` |
| `Datastore.AllocateTemplate` | Convert the finished VM into a template |
| `Datastore.Audit` | Read storage info (space checks, ISO lookup) |
| `Sys.Modify` | Node-level changes the plugin makes around VM lifecycle (e.g. temporary firewall/network state during boot) |
| `SDN.Use` | Attach the VM's NIC to `network_bridge` (`vmbr0`) — required once the bridge is managed as an SDN zone; without it VM creation fails with `403 Permission check failed (/sdn/zones/<zone>/vmbr0, SDN.Use)` |

Not granted: `VM.Config.Cloudinit` and `Pool.Allocate` — the template doesn't
use Proxmox-native cloud-init (`cloud_init = false`, autoinstall drives OS
setup instead) or a resource pool, so neither privilege is exercised.

## Troubleshooting a failed build

By default, when a build fails Packer stops the VM and deletes it — so
there's nothing left to inspect. Rerun with `-on-error=ask` to pause instead:

```bash
packer build -on-error=ask .
```

On failure you'll get a `[c]lean up, [a]bort, [r]etry, or [b]uild debug`
prompt; the VM stays up until you answer it. While it's paused, SSH in
(same user/key as `variables.auto.pkrvars.hcl`) using the IP shown in the
Proxmox UI for that VM ID, and check what actually failed:

```bash
ssh -i ~/.ssh/<your_key> <username>@<vm-ip> 'sudo cloud-init status --long'
```

`cloud-init status --long` names the specific stage/module that errored —
much more direct than grepping `/var/log/cloud-init.log` or
`/var/log/cloud-init-output.log` blind, since a `SUCCESS`-looking tail of
either file (e.g. the final `modules-final` stage finishing with "0
failures") doesn't mean the *overall* run succeeded; the actual failure can
be in an earlier stage that scrolled past. Once you're done inspecting,
answer the Packer prompt with `c` to clean up the VM.
