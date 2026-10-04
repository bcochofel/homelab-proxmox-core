# Packer

First stage of the Packer -> Terraform -> Ansible pipeline: builds the
Proxmox VM template that Terraform later clones.

`packer/ubuntu-26.04/` is the one template this repo builds — its own
`*.pkr.hcl`/`variables.pkr.hcl`/`variables.pkrvars.hcl.example` and a README
with build instructions and the full deep-dive (what it builds, file map,
ADRs, variables reference). This doc covers what's shared with any future
template that might be added under `packer/`.

## Shared setup

- Credentials: `sops exec-env ~/.secrets/packer.yaml '<command>'` passes
  `PKR_VAR_proxmox_api_url`, `_api_token_id`, `_api_token_secret`, `_node`,
  `_skip_tls_verify` and `PKR_VAR_password_hash` to that one command only
  — see [`CREDENTIALS.md`](CREDENTIALS.md).
- Run `packer init .` (plugin download, non-mutating, no credentials) and
  `sops exec-env ~/.secrets/packer.yaml 'packer build .'` directly from the
  template's own directory — neither is a mise task, so the one command
  that actually writes to Proxmox stays explicit.

## Proxmox privileges

Packer authenticates as `packer@pve!packer`, holding the `PackerBuild`
role — separate from OpenTofu's identity, so each tool's blast radius
matches what it actually needs. The `pveum` commands that create the role,
user and token are in [`CREDENTIALS.md`](CREDENTIALS.md); this table
explains each privilege.

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
