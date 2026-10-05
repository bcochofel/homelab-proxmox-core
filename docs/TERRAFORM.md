# Terraform — Caddy + DNS VMs on Proxmox (bpg/proxmox)

Clones the Packer template (`ubuntu-26.04`) into two VMs — `proxy` and
`dns` — assigns each a static IP via cloud-init, and generates
`../ansible/inventory/hosts.ini`.

| VM | Role | IP | Ansible group |
| --- | --- | --- | --- |
| proxy | Caddy reverse proxy | 192.168.68.16 | `caddy` |
| server01 | CoreDNS + Pihole (VM's own IP; each container gets a separate Docker macvlan IP, `.2`/`.5`, not visible to Terraform) | 192.168.68.15 | `dns` |

- `modules/vm/` — reusable single-VM clone module, generic (any role), with
  no workload-specific inputs. It just clones the
  template with a static IP; role differs only in the `tags` passed in and
  which Ansible group the node lands in. Called twice here (`module.caddy`,
  `module.dns`) — the DNS containers' macvlan IPs are Docker-level config
  applied by Ansible, not a Terraform/Proxmox-level concern, so `dns_node`
  only carries the one VM-level IP.
- `templates/inventory.ini.tftpl` — renders the Ansible inventory (INI
  format): `[caddy]` and `[dns]` groups.
- State: HCP Terraform workspace `core-caddy` (state only — Execution Mode
  is Local, since Proxmox is LAN-only and HCP's infra can't reach it).

Decoupled from Ansible by design — run `tofu apply`, then the Ansible
playbooks separately (no `local-exec` chaining).

Always `tofu plan` and review the output before applying; never
`destroy`.

## Engine: OpenTofu with HCP Terraform state

The CLI is [OpenTofu](https://opentofu.org) (`tofu`), pinned in
`mise.toml`. State lives in the HCP Terraform workspace `core-caddy`
(execution mode Local), reached through the `cloud {}` block in
`versions.tf`. Every apply is run by hand from a laptop.

- **`hostname = "app.terraform.io"` in the `cloud {}` block.** OpenTofu
  has no default hostname for the cloud backend and refuses to init
  without one.
- **Auth:** `TF_TOKEN_app_terraform_io`, from `~/.secrets/homelab-ro.yaml`
  (read-only team token: `tofu:init`, `tofu:plan-ro`) or
  `~/.secrets/homelab.yaml` (your user token: `tofu:plan`, `tofu:apply`) —
  see
  [`CREDENTIALS.md`](CREDENTIALS.md). Don't keep a
  `~/.terraform.d/credentials.tfrc.json`: it's an ambient read-write
  credential.
- **`.terraform.lock.hcl` records `registry.opentofu.org/...` providers**,
  with `bpg/proxmox` pinned at `0.111.1`. Bump it deliberately with
  `tofu init -upgrade`.
- **pre-commit uses `tofu`** — `--hook-config=--tf-path=tofu` on the
  `terraform_fmt`/`terraform_validate`/`terraform_docs`/`terraform_tflint`
  hooks in `.pre-commit-config.yaml`. Set there rather than as an env var
  so it also applies to commits made from a shell or IDE without
  `mise activate`; otherwise the hooks fall back to `terraform` and
  rewrite the lock files to `registry.terraform.io`.
- **Known warning:** `tofu init` reports that bpg's provider signing key on
  the OpenTofu registry has expired and that this will become an error in
  a future OpenTofu release. Nothing to do locally — it's on the provider
  side.
- **Rollback path:** `terraform` stays pinned in `mise.toml`. Switching
  means restoring `registry.terraform.io` entries in `.terraform.lock.hcl`
  (`terraform init` rewrites it) and dropping the `--tf-path=tofu` hook
  args.

## Configuration: `example.tfvars` vs `terraform.tfvars` vs secrets

Three different places feed this module's inputs, split by sensitivity:

- **`example.tfvars`** — committed to git. The root `.gitignore` blanket-
  ignores `*.tfvars`, then explicitly re-includes this one file
  (`!example.tfvars`), so it's the one `.tfvars` that's actually meant to be
  checked in. It's a template with realistic placeholder values for every
  *non-secret* input (`target_node`, `vm_template`, `gateway`,
  `network_bridge`, `nameserver`, `searchdomain`, `ciuser`, an example
  `sshkeys` value) plus the `caddy_node`/`dns_node` default shapes. Never
  put a real secret in it — edit it only to change the example values
  everyone starts from.
- **`terraform.tfvars`** — what you actually run against. Gitignored
  (`terraform/terraform.tfvars` is listed explicitly, on top of the
  blanket `*.tfvars` rule). Create it once with
  `cp example.tfvars terraform.tfvars`, then fill in your real
  `target_node` and a real `sshkeys` value (not the placeholder), plus any
  `caddy_node`/`dns_node` override you need. `sshkeys` is the one Terraform
  input in
  this module that's *not* marked `sensitive` in `variables.tf` — that's
  exactly why it belongs here rather than in `~/.secrets/`: it's a
  public key, there's nothing to encrypt.
- **`~/.secrets/` via the `mise run tofu:*` tasks** — everything OpenTofu treats as
  `sensitive` (`proxmox_api_token`, `cipassword`), plus the HCP Terraform
  token (`TF_TOKEN_app_terraform_io`, read by the `tofu` CLI itself, not by
  any `var.*`). These never touch a `.tfvars` file — they arrive as
  environment variables. See [`CREDENTIALS.md`](CREDENTIALS.md).

OpenTofu picks up `terraform.tfvars` and `TF_VAR_*` env vars automatically
— no `-var-file` flag needed. Run `mise run tofu:plan` / `tofu:apply`
from anywhere in the repo.

## Proxmox privileges

`tofu apply` authenticates as `bcochofel@pve!console`, holding the
`TofuApply` role; read-only `tofu plan` runs as `ai-agent@pve!ai-agent`
(`AiAgentRO`). The `pveum` commands that create both are in
[`CREDENTIALS.md`](CREDENTIALS.md); this table explains `TofuApply`'s
privileges. `variables.tf` expects the token in the combined
`user@realm!tokenid=secret` form (`TF_VAR_proxmox_api_token`).

| Privilege | Why OpenTofu needs it |
| --- | --- |
| `VM.Allocate` | Required on the *destination* VMID for a clone, not just fresh-built VMs — Proxmox's clone endpoint checks `VM.Clone` on the source template but `VM.Allocate` on the new VMID, since claiming a not-yet-existing VM ID is an "allocate" regardless of whether the VM ends up empty or cloned. A `VM.Clone`-only role fails the clone with a 403. |
| `VM.Audit` | Look up the template's VMID by name (`data.proxmox_virtual_environment_vms.template`), read VM state while polling for the cloud-init-assigned IP |
| `VM.Clone` | Read/export permission on the *source* template |
| `VM.Config.CDROM` | If the `ubuntu-26.04` template carries a leftover `ide`-bus slot from the Packer build, bpg's `initialization` block reconfigures the cloud-init drive on that same bus on every clone, which Proxmox checks under the CD-ROM permission bucket regardless of actual media type. |
| `VM.Config.CPU`, `VM.Config.Memory`, `VM.Config.Disk`, `VM.Config.HWType`, `VM.Config.Network` | Set cores, memory, resize the cloned disk, attach the network device |
| `VM.Config.Cloudinit` | Write the static IP/gateway, DNS, and cloud-init user-account config the clone boots with |
| `VM.Config.Options` | Set description/tags on the clone |
| `VM.PowerMgmt` | Start the clone |
| `VM.GuestAgent.Audit` | Poll the QEMU guest agent until it reports the clone's IP (read-only agent commands only) |
| `Datastore.Allocate`, `Datastore.AllocateSpace` | Allocate the cloned VM's disk + cloud-init drive on `datastore_id` |
| `Datastore.Audit` | Read storage info |
| `SDN.Use` | Attach the VM's NIC to `vmbr0` — same reason Packer needs it: required once the bridge is managed as an SDN zone |

Not granted: anything from Packer's role that's about *building* a template
from an ISO (`VM.Console`, `Datastore.AllocateTemplate`, `Sys.Modify`) —
Terraform only ever clones an already-built template, it never creates one.

`providers.tf`'s `ssh { agent = true, username = var.proxmox_ssh_username }`
block is configured but not currently exercised — this repo's cloud-init
only sets IP/DNS/user-account via the API (`initialization` block), no
custom snippet/file upload.

## Security checks and policy enforcement

Terraform under `terraform/` is scanned by TFLint, Trivy, and Checkov (see
[`CONTRIBUTING.md`](../CONTRIBUTING.md)'s pre-commit section). Trivy and
Checkov ship no built-in checks for the `bpg/proxmox` provider — Aqua's
check database (`avd.aquasec.com`) has no Proxmox category (nor a VMware
one, for what it's worth), so anything Proxmox-specific has to be a custom
check. Custom policies live under `policies/`:

- `policies/checkov/proxmox_*.yaml` — one file per check, targeting
  `proxmox_virtual_environment_vm`: UEFI firmware (`bios = "ovmf"`,
  MEDIUM), the QEMU guest agent enabled (MEDIUM), a `description` set
  (LOW), and the modern `q35` machine type (LOW). `checkov.yaml`'s
  `check: [MEDIUM, HIGH, CRITICAL]` genuinely filters which checks run —
  despite checkov's own "Filtering checks by severity is only possible
  with an API key" log line, that message is misleading for custom checks: a check with no `severity` (or one below
  the configured floor) in its metadata is silently excluded, not merely
  unfiltered. The two LOW checks here (description, machine type) are
  intentionally not enforced as a result. `CKV_PROXMOX_1` (UEFI) is
  skip-listed in `checkov.yaml`: `modules/vm/main.tf` doesn't set
  `bios = "ovmf"`. Remove the skip once the module sets it (and, per
  `PROXMOX-004`, an `efi_disk` block).
- `policies/trivy/proxmox_*.rego` — the same intent, written as Trivy custom
  Rego checks (one package per file), plus two provider-level checks (no
  hardcoded `api_token`, no `insecure = true`). **Caveat:** custom Rego
  checks have not been shown to fire against Trivy 0.72.0 via the documented
  `--config-check`/`--check-namespaces`/`--raw-config-scanners` flags — even
  a trivial always-true test policy produces no result (see
  aquasecurity/trivy discussions #6453 and #7087). Treat these `.rego`
  files as unverified; Checkov is the enforcing gate.

The `terraform_checkov` pre-commit hook needs an *absolute*
`--external-checks-dir` (`.pre-commit-config.yaml` passes
`__GIT_WORKING_DIR__/policies/checkov`), since
`antonbabenko/pre-commit-terraform`'s hook script `cd`s into each changed
directory before running `checkov -d .` — a relative path in `checkov.yaml`
alone would silently resolve to nothing there.
