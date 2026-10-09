# Terraform — Caddy + DNS VMs on Proxmox (bpg/proxmox)

Clones the Packer template (`ubuntu-26.04`) into three VMs — `proxy`,
`dns` and the CI runner `runner01` — assigns each a static IP via
cloud-init, and generates
`../ansible/inventory/hosts.ini`.

| VM | Role | IP | Ansible group |
| --- | --- | --- | --- |
| proxy | Caddy reverse proxy | 192.168.68.16 | `caddy` |
| server01 | CoreDNS + Pihole (VM's own IP; each container gets a separate Docker macvlan IP, `.2`/`.5`, not visible to Terraform) | 192.168.68.15 | `dns` |
| runner01 | Self-hosted GitHub Actions runner for CI dry-runs ([`RUNNER.md`](RUNNER.md)); outbound connections only | 192.168.68.9 | `github_runner` |

- `modules/vm/` — reusable single-VM clone module, generic (any role), with
  no workload-specific inputs. It just clones the
  template with a static IP; role differs only in the `tags` passed in and
  which Ansible group the node lands in. Called three times here
  (`module.caddy`, `module.server01`, `module.runner01`) — the DNS containers' macvlan IPs are Docker-level config
  applied by Ansible, not a Terraform/Proxmox-level concern, so `dns_node`
  only carries the one VM-level IP.
- `templates/inventory.ini.tftpl` — renders the Ansible inventory (INI
  format): `[caddy]`, `[dns]` and `[github_runner]` groups.
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
- **Auth:** `TF_TOKEN_app_terraform_io`, your user token from
  `~/.secrets/homelab.yaml` (`tofu:init`, `tofu:plan`, `tofu:apply`). The
  AI agent has no HCP token (the Free plan can't issue a read-only one), so
  it only runs `tofu init -backend=false` and `tofu validate` — see
  [`CREDENTIALS.md`](CREDENTIALS.md). Don't keep a
  `~/.terraform.d/credentials.tfrc.json`: it's an ambient read-write
  credential.
- **`.terraform.lock.hcl` records `registry.opentofu.org/...` providers**,
  with `bpg/proxmox` pinned there. Bump it deliberately with
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

## Configuration: defaults and secrets, no tfvars

Two places feed this module's inputs, split by sensitivity:

- **`variables.tf` defaults** — every non-secret input, committed:
  `proxmox_endpoint`, `target_node`, `vm_template`, the network
  (`gateway`, `network_bridge`, `nameserver`, `searchdomain`), `ciuser`,
  `sshkeys` (public keys, nothing to hide) and the
  `caddy_node`/`dns_node`/`runner_node` definitions. You, CI and the AI
  agent's `tofu validate` all see the same values, so there's no
  `terraform.tfvars` to create or keep in step. To change one, change its
  default in a pull request.
- **`~/.secrets/` via the `mise run tofu:*` tasks** — everything OpenTofu treats as
  `sensitive` (`proxmox_api_token`, `cipassword`), plus the HCP Terraform
  token (`TF_TOKEN_app_terraform_io`, read by the `tofu` CLI itself, not by
  any `var.*`). They arrive as `TF_VAR_*` environment variables, never in
  a file in the repo. See [`CREDENTIALS.md`](CREDENTIALS.md).

**Don't add a `terraform.tfvars`.** OpenTofu loads one automatically, and
its values would override the defaults on your machine only, so your plan
and CI's would differ. `*.tfvars` stays gitignored so a stray one is never
committed. HCP Terraform workspace variables don't apply either: the
workspace runs in Local execution mode, and those only reach runs HCP
executes.

No `-var-file` flag is needed. Run `mise run tofu:plan` / `tofu:apply`
from anywhere in the repo; each passes your age key explicitly, since it
isn't at SOPS's default path ([`CREDENTIALS.md`](CREDENTIALS.md) step 4).

`tofu:plan` saves the plan to `terraform/tfplan` (`tofu plan -out=tfplan`),
and `tofu:apply` applies that file (`tofu apply tfplan`), so what gets
applied is exactly the plan you reviewed. A saved plan doesn't ask for
confirmation, and `tofu` refuses it if the state changed since the plan
was made: run `tofu:plan` again. `terraform/tfplan` is gitignored, since
plan files can hold sensitive values.

The tasks take no extra arguments. For a one-off flag, run the underlying
command with your key:

```bash
cd terraform && SOPS_AGE_KEY_FILE=~/.config/sops/age/bcochofel.txt \
  sops exec-env ~/.secrets/homelab.yaml 'tofu plan -target=module.caddy'
```

## Proxmox privileges

`tofu apply` authenticates as `terraform@pve!terraform`, holding the
`TofuApply` role. The `pveum` commands that create it are in
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
  checks have not been shown to fire against the pinned Trivy (`mise.toml`) via the documented
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
