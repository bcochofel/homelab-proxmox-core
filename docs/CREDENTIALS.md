# Credentials

How to create every credential Packer, OpenTofu and Ansible need, where
each one is stored, and how it reaches the tool that uses it. Follow it
top to bottom on a clean Proxmox node before the first `packer build`.

Written for **Proxmox VE 8.x** (see [Proxmox VE 9](#proxmox-ve-9) for
what changes after an upgrade).

## The model

One identity per **role**, never one shared admin credential:

| Principal | Proxmox token | Role | HCP Terraform | Used for |
| --- | --- | --- | --- | --- |
| Packer | `packer@pve!packer` | `PackerBuild` | none | `packer build` (template only) |
| Console (you) | `bcochofel@pve!console` | `TofuApply` | your user token | `tofu apply` |
| AI agent | `ai-agent@pve!ai-agent` | `AiAgentRO` | read-only team token | `tofu plan`, read-only investigation |

Read and write credentials live in **separate SOPS files**, because SOPS
recipients are set per file:

| File | Holds | Encrypted to |
| --- | --- | --- |
| `~/.secrets/homelab-ro.yaml` | Proxmox endpoint/node, `ai-agent` token, HCP read-only token | you + the `ai-agent` age key |
| `~/.secrets/homelab.yaml` | Packer and console tokens, HCP read-write token, cloud-init password, template password hash | you only |
| `ansible/inventory/group_vars/<group>.sops.yaml` (committed) | Ansible-only secrets for this repo: Cloudflare token (`caddy`), Pihole password (`pihole`) | you only |

The split: credentials for non-Ansible tools, or shared across repos, go
in `~/.secrets/`; secrets only Ansible uses, for this repo only, go in
the encrypted `group_vars` file of the group that needs them, so no other
host ever sees them.

Nothing is exported into your shell automatically. Read-only credentials
are loaded on request (`hl_ro`); write credentials are passed to exactly
one command by a wrapper (`packer_rw`, `tofu_rw`) and never exported.
Ansible decrypts its own secrets at task time. A process started from your shell, including an AI agent,
therefore never inherits a write credential.

## 1. Proxmox: roles, users, tokens

`pveum` only exists on the Proxmox node. Run the commands below over
`ssh root@<pve-host>`, from the node's web shell (*node → >_ Shell*), or do
the same through *Datacenter → Permissions* in the web UI.

### Roles

```bash
# Build a template from an ISO: create/configure/boot the VM, type the boot
# command on its console, read the guest agent, convert it to a template.
pveum role add PackerBuild -privs "VM.Allocate,VM.Audit,VM.Config.CDROM,\
VM.Config.CPU,VM.Config.Disk,VM.Config.HWType,VM.Config.Memory,\
VM.Config.Network,VM.Config.Options,VM.Console,VM.Monitor,VM.PowerMgmt,\
Datastore.AllocateSpace,Datastore.AllocateTemplate,Datastore.Audit,\
Sys.Modify,SDN.Use"

# Clone the template into VMs and manage them: never builds a template.
pveum role add TofuApply -privs "VM.Allocate,VM.Audit,VM.Clone,\
VM.Config.CDROM,VM.Config.CPU,VM.Config.Cloudinit,VM.Config.Disk,\
VM.Config.HWType,VM.Config.Memory,VM.Config.Network,VM.Config.Options,\
VM.Monitor,VM.PowerMgmt,Datastore.Allocate,Datastore.AllocateSpace,\
Datastore.Audit,SDN.Use"

# Read-only: enough for `tofu plan` and investigation, nothing that changes
# state or runs anything inside a VM.
pveum role add AiAgentRO -privs "VM.Audit,Datastore.Audit,Sys.Audit,\
Pool.Audit,SDN.Audit"
```

What each privilege is for: [`PACKER.md`](PACKER.md#proxmox-privileges)
(`PackerBuild`) and [`TERRAFORM.md`](TERRAFORM.md#proxmox-privileges)
(`TofuApply`).

**`AiAgentRO` deliberately has no `VM.Monitor`.** On Proxmox VE 8 that
privilege also grants every guest-agent command, including running
programs inside the VM, so it isn't read-only. The trade-off: `tofu plan`
as `ai-agent` can't read guest-agent IPs. If the plan fails on a
guest-agent permission error, that's this boundary working. Leave it
failing rather than adding `VM.Monitor`; Proxmox VE 9 fixes it (see below).

### Users and tokens

Tokens are created with **privilege separation** (`--privsep 1`): a token
gets only the permissions granted to the token itself, capped by its
user's. Each identity therefore gets two ACL entries, one for the user
and one for the token.

```bash
pveum user add packer@pve   --comment "Packer template builds (token only)"
pveum user add bcochofel@pve --comment "Console: tofu apply (token only)"
pveum user add ai-agent@pve --comment "AI agent: read-only (token only)"

pveum user token add packer@pve    packer   --privsep 1 --comment "packer build"
pveum user token add bcochofel@pve console  --privsep 1 --comment "tofu apply"
pveum user token add ai-agent@pve  ai-agent --privsep 1 --comment "tofu plan / investigation"

pveum acl modify / --users  'packer@pve'           --roles PackerBuild
pveum acl modify / --tokens 'packer@pve!packer'    --roles PackerBuild
pveum acl modify / --users  'bcochofel@pve'        --roles TofuApply
pveum acl modify / --tokens 'bcochofel@pve!console' --roles TofuApply
pveum acl modify / --users  'ai-agent@pve'         --roles AiAgentRO
pveum acl modify / --tokens 'ai-agent@pve!ai-agent' --roles AiAgentRO
```

Each `token add` prints the secret **once**. Copy it straight into the
matching SOPS file in step 5; it can't be retrieved later, only
regenerated.

The users have no password: they can only authenticate with their token,
so there's no interactive login to protect.

Check the result:

```bash
pveum acl list
pveum user token permissions ai-agent@pve ai-agent --path /
pveum user token permissions bcochofel@pve console --path /
pveum user token permissions packer@pve packer --path /
```

## 2. HCP Terraform: workspace and tokens

State lives in HCP Terraform (organization `homelab-bcochofel-com`,
workspace `core-caddy`); OpenTofu reads the token from
`TF_TOKEN_app_terraform_io`.

- **Workspace:** create `core-caddy` in the organization as a
  CLI-driven workspace, then set *Settings → General → Execution Mode* to
  **Local**. Proxmox is LAN-only, so HCP's runners can't reach it; HCP
  only stores state. The workspace name must match `versions.tf`.
- **Read-write:** a user API token for your account
  (*User settings → Tokens*). It goes in `~/.secrets/homelab.yaml`.
- **Read-only:** a team API token for a dedicated `ai-agent` team that
  has **Read** access to the `core-caddy` workspace (and nothing else). It
  goes in `~/.secrets/homelab-ro.yaml`. Teams aren't available on every
  HCP plan, so check yours. Read access can't lock state, which is why
  read-only plans run with `-lock=false`.
- Remove `~/.terraform.d/credentials.tfrc.json` if `tofu login` (or
  `terraform login`) ever created it. That file is an ambient read-write
  credential that every process can pick up.

## 3. Cloudflare API token

Caddy proves ownership of `*.homelab.bcochofel.com` to Let's Encrypt with
DNS-01 TXT records it writes through the Cloudflare API. The token needs to
read the zone (to find it) and edit its DNS records, in `bcochofel.com`
only.

In the Cloudflare dashboard (**My Profile → API Tokens → Create Token**):

1. **Token name:** something that says where it's used, e.g.
   `homelab-proxmox-core caddy dns-01`.
2. **Permissions:** from the **DNS and Zones** group, add exactly these
   two:
   - **DNS Write**
   - **Zone Read**
3. **Resources:** the zone `bcochofel.com` in your account — that one
   zone only, not all zones.
4. **Client IP filtering** (optional): your home public IP, since the
   token is only ever used from inside the LAN.
5. **Expiry** (optional): none, or an end date you plan to rotate by.
6. Review the summary: it should show `bcochofel.com` with **DNS Write**
   and **Zone Read** and nothing else. Then create the token.

The token is shown **once**. Put it straight into
`ansible/inventory/group_vars/caddy.sops.yaml` as `cloudflare_api_token`
(step 5). One token per repo: the workloads repo gets its own, so either
can be revoked without touching the other.

## 4. Age keys

- **Your key:** `~/.config/sops/age/keys.txt` (`chmod 600`). If you don't
  have one yet:

  ```bash
  age-keygen -o ~/.config/sops/age/keys.txt && chmod 600 ~/.config/sops/age/keys.txt
  ```

- **`ai-agent` key:** a separate key that only ever decrypts
  `~/.secrets/homelab-ro.yaml`. It's created now so the read-only file has
  the right recipients from the start; it's mounted into the agent's
  devcontainer later.

  ```bash
  age-keygen -o ~/.config/sops/age/ai-agent.txt && chmod 600 ~/.config/sops/age/ai-agent.txt
  ```

  Never add the `ai-agent` private key to `keys.txt`.

`age-keygen` prints each public key (`age1...`). Use them below.

## 5. Secret files

```bash
mkdir -p ~/.secrets && chmod 700 ~/.secrets
```

`~/.secrets/.sops.yaml`: SOPS looks for its config starting from the
current directory, so create and edit these files from `~/.secrets`.

```yaml
creation_rules:
  - path_regex: homelab-ro\.yaml$
    age: <your-public-key>,<ai-agent-public-key>
  - path_regex: homelab\.yaml$
    age: <your-public-key>
```

Create each file with `cd ~/.secrets && sops <file>`:

`~/.secrets/homelab-ro.yaml`:

```yaml
proxmox_endpoint: https://192.168.68.20:8006/
proxmox_node: pve1
ai_agent_token_id: ai-agent@pve!ai-agent
ai_agent_token_secret: <printed by pveum>
hcp_ro_token: <ai-agent team token>
```

`~/.secrets/homelab.yaml`:

```yaml
packer_token_id: packer@pve!packer
packer_token_secret: <printed by pveum>
console_token_id: bcochofel@pve!console
console_token_secret: <printed by pveum>
hcp_token: <your user token>
cloudinit_password: <password for the cloud-init user on cloned VMs>
password_hash: <mkpasswd -m sha-512 '<password>' for the template user>
```

Ansible's secrets are inventory variables, so each lives next to the rest
of its group's variables, encrypted. Create them from the repo root, where
the repo's `.sops.yaml` applies:

```bash
sops ansible/inventory/group_vars/caddy.sops.yaml
sops ansible/inventory/group_vars/pihole.sops.yaml
```

`caddy.sops.yaml`:

```yaml
cloudflare_api_token: <Cloudflare token from step 3>
```

`pihole.sops.yaml`:

```yaml
pihole_webpassword: <Pihole admin password>
```

The `community.sops` vars plugin (`ansible/ansible.cfg`) decrypts them with
your age key only while a task runs (`vars_stage = task`), so
`ansible-lint`, `--syntax-check` and `ansible-inventory` never decrypt them.
They're encrypted to your key only — never to the `ai-agent` key — because
a service password or API token has no read-only form.

Back up `~/.secrets/` and both age keys somewhere safe. Without the age
keys, none of these files can be decrypted.

## 6. Shell helpers

Save this as `~/.secrets/homelab.sh` and add `source ~/.secrets/homelab.sh`
to `~/.zshrc`. Sourcing it defines functions only; it decrypts nothing
until one of them runs.

```bash
# Decrypt one key from ~/.secrets/<file>.yaml
_hl() { sops -d --extract "[\"$2\"]" "$HOME/.secrets/$1.yaml"; }

# Read-only identity: safe to export into the interactive shell.
# cipassword gets a placeholder: plans run against it, applies never do.
hl_ro() {
  export TF_VAR_proxmox_api_token="$(_hl homelab-ro ai_agent_token_id)=$(_hl homelab-ro ai_agent_token_secret)"
  export TF_TOKEN_app_terraform_io="$(_hl homelab-ro hcp_ro_token)"
  export TF_VAR_cipassword="placeholder-not-a-real-password"
}

hl_clear() {
  unset TF_VAR_proxmox_api_token TF_TOKEN_app_terraform_io TF_VAR_cipassword
}

# Write credentials: passed to ONE command, never exported.
packer_rw() {
  PKR_VAR_proxmox_api_url="$(_hl homelab-ro proxmox_endpoint)api2/json" \
  PKR_VAR_proxmox_node="$(_hl homelab-ro proxmox_node)" \
  PKR_VAR_proxmox_skip_tls_verify=true \
  PKR_VAR_proxmox_api_token_id="$(_hl homelab packer_token_id)" \
  PKR_VAR_proxmox_api_token_secret="$(_hl homelab packer_token_secret)" \
  PKR_VAR_password_hash="$(_hl homelab password_hash)" \
    packer "$@"
}

tofu_rw() {
  TF_VAR_proxmox_api_token="$(_hl homelab console_token_id)=$(_hl homelab console_token_secret)" \
  TF_VAR_cipassword="$(_hl homelab cloudinit_password)" \
  TF_TOKEN_app_terraform_io="$(_hl homelab hcp_token)" \
    tofu "$@"
}
```

Ansible needs no wrapper: it decrypts its secrets from the `group_vars`
`*.sops.yaml` files itself (step 5).

`password_hash` comes from the environment, so remove it from
`packer/ubuntu-26.04/variables.auto.pkrvars.hcl`: a value in a varfile
takes precedence over `PKR_VAR_*`.

## 7. Running the pipeline

```bash
# Packer: build the template
cd packer/ubuntu-26.04
packer init .
packer_rw build .

# OpenTofu: review read-only, apply read-write
cd ../../terraform
hl_ro
tofu init
tofu plan -lock=false     # as ai-agent; diffs on cipassword are expected
tofu_rw plan              # the plan you're about to apply, as console
tofu_rw apply

# Ansible
cd ../ansible
ansible-playbook playbooks/site.yml
```

`tofu_rw plan` is the one to review before applying. The `ai-agent` plan
runs against a placeholder `cipassword`, so it shows a change there even
when nothing else changed.

## 8. Verify the boundary

Run these once after setup. A failure means a credential is wider than
intended.

```bash
hl_clear; env | grep -E 'PROXMOX|TF_VAR|TF_TOKEN|PKR_VAR'  # nothing
hl_ro;    env | grep -E 'TF_VAR_proxmox_api_token' | cut -d= -f1-2  # ai-agent@pve!ai-agent only

# Read-only identity can't write:
cd terraform && tofu apply   # must fail before any change (HCP refuses the state
                             # lock); if it ever reaches the prompt, answer "no"

# The ai-agent age key can't open the write file:
SOPS_AGE_KEY_FILE=~/.config/sops/age/ai-agent.txt sops -d ~/.secrets/homelab.yaml   # must fail
SOPS_AGE_KEY_FILE=~/.config/sops/age/ai-agent.txt sops -d ~/.secrets/homelab-ro.yaml >/dev/null && echo ok
```

## Proxmox VE 9

Proxmox VE 9 drops `VM.Monitor`; the `pve8to9` checker flags custom roles
that use it. After upgrading:

- In `PackerBuild` and `TofuApply`, replace `VM.Monitor` with
  `VM.GuestAgent.Audit` (read guest-agent information, such as the VM's
  IP).
- Add `VM.GuestAgent.Audit` to `AiAgentRO`. On 9.x it's informational
  only, so read-only `tofu plan` can read guest-agent IPs too.
- Never grant `VM.GuestAgent.Unrestricted`, `FileRead` or `FileWrite` to
  any of these roles.

`pveum role modify <role> -privs "<full list>"` replaces a role's
privileges in place.
