# Packer

First stage of the Packer -> Terraform -> Ansible pipeline: builds the
Proxmox VM template that Terraform later clones.

`packer/ubuntu-26.04/` is the one template this repo builds — its own
`*.pkr.hcl`/`variables.pkr.hcl`/`variables.pkrvars.hcl.example` and a README
with build instructions and the full deep-dive (what it builds, file map,
ADRs, variables reference). This doc covers what's shared with any future
template that might be added under `packer/`.

## Shared setup

- Build with `mise run packer:build`: it runs `packer init .` and then
  `packer build .` in `packer/ubuntu-26.04/`, with `sops exec-env` passing
  `PKR_VAR_proxmox_api_url`, `_api_token_id`, `_api_token_secret`,
  `_node`, `_skip_tls_verify` and `PKR_VAR_password_hash` from
  `~/.secrets/homelab.yaml` to that one command only — see
  [`CREDENTIALS.md`](CREDENTIALS.md).

## Configuration: `variables.pkrvars.hcl.example` vs `variables.auto.pkrvars.hcl` vs secrets

Each template's inputs come from four places, split by sensitivity
(paths below are for `packer/ubuntu-26.04/`):

- **`variables.pkr.hcl`** — committed. Declares every variable, with a
  default for everything that isn't required or secret (VM sizing,
  packages, the build VM's static network, the Elastic Agent version, ...).
  Change a default here when it should change for everyone.
- **`variables.pkrvars.hcl.example`** — committed. The root `.gitignore`
  ignores `*.pkrvars.hcl`, and the `.example` suffix keeps this file out of
  that rule. It holds realistic values for the per-build, non-secret
  inputs, including the required `ssh_private_key_file` and the
  `ssh_authorized_keys` you'll want. Never put a real secret in it.
- **`variables.auto.pkrvars.hcl`** — what you actually build with.
  Gitignored by the same `*.pkrvars.hcl` rule, and loaded by Packer
  automatically (the `.auto.` part), so no `-var-file` flag is needed.
  Create it once with
  `cp variables.pkrvars.hcl.example variables.auto.pkrvars.hcl` and fill in
  your key path and public keys, plus any default you want to override.
- **`~/.secrets/homelab.yaml` via `mise run packer:build`** — the Proxmox
  connection (`PKR_VAR_proxmox_api_url`, `_api_token_id`,
  `_api_token_secret`, `_node`, `_skip_tls_verify`) and
  `PKR_VAR_password_hash`, passed as environment variables to that one
  command. See [`CREDENTIALS.md`](CREDENTIALS.md).

**Keep `password_hash` and the `proxmox_*` variables out of
`variables.auto.pkrvars.hcl`.** A value in a varfile takes precedence over
`PKR_VAR_*`, so it would silently replace the one in `~/.secrets/`.

`mise run packer:build` takes no extra arguments. For a one-off flag, run
the underlying command with your key:

```bash
cd packer/ubuntu-26.04 && SOPS_AGE_KEY_FILE=~/.config/sops/age/bcochofel.txt \
  sops exec-env ~/.secrets/homelab.yaml 'packer build -on-error=ask .'
```

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
| `VM.Console` | Send the boot-command keystrokes during autoinstall |
| `VM.GuestAgent.Audit` | Read the VM's IP from the QEMU guest agent (read-only agent commands only). `ubuntu-26.04` doesn't need it to SSH in, since it connects to its static build IP (`ssh_host`, template README ADR-4); every role keeps it as the read-only way to see VM IPs |
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
there's nothing left to inspect. Rerun with `-on-error=ask` to pause
instead, using the one-off command under
[Configuration](#configuration-variablespkrvarshclexample-vs-variablesautopkrvarshcl-vs-secrets).

On failure you'll get a `[c]lean up, [a]bort, [r]etry, or [b]uild debug`
prompt; the VM stays up until you answer it. While it's paused, SSH in
(same user/key as `variables.auto.pkrvars.hcl`) at the build VM's static
IP (`build_ip_cidr`, `192.168.71.1` for `ubuntu-26.04`; template README
ADR-4), and check what actually failed:

```bash
ssh -i ~/.ssh/<your_key> <username>@192.168.71.1 'sudo cloud-init status --long'
```

`cloud-init status --long` names the specific stage/module that errored —
much more direct than grepping `/var/log/cloud-init.log` or
`/var/log/cloud-init-output.log` blind, since a `SUCCESS`-looking tail of
either file (e.g. the final `modules-final` stage finishing with "0
failures") doesn't mean the *overall* run succeeded; the actual failure can
be in an earlier stage that scrolled past. Once you're done inspecting,
answer the Packer prompt with `c` to clean up the VM.
