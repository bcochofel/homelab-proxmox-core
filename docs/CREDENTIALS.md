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
| `~/.secrets/packer.yaml` | Everything `packer build` needs: endpoint, node, Packer token, template password hash | you only |
| `~/.secrets/tofu.yaml` | Everything `tofu apply` needs: console token, cloud-init password, HCP read-write token | you only |
| `~/.secrets/tofu-ro.yaml` | Read-only `tofu plan`: `ai-agent` token, placeholder cloud-init password, HCP read-only token | you + the `ai-agent` age key |
| `ansible/inventory/group_vars/<group>.sops.yaml` (committed) | Ansible-only secrets for this repo: Cloudflare token (`caddy`), Pihole password (`pihole`) | you only |

The split: credentials for non-Ansible tools, or shared across repos, go
in `~/.secrets/`; secrets only Ansible uses, for this repo only, go in
the encrypted `group_vars` file of the group that needs them, so no other
host ever sees them.

Nothing is ever exported into your shell. Each command gets its
credentials from `sops exec-env`, which decrypts one file and passes its
keys as environment variables to that command only. One file per tool
means `packer build` never sees the OpenTofu token and vice versa. Ansible
decrypts its own secrets at task time. A process started from your shell,
including an AI agent, never inherits a credential.

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
  (*User settings → Tokens*). It goes in `~/.secrets/tofu.yaml`.
- **Read-only:** a team API token for a dedicated `ai-agent` team that
  has **Read** access to the `core-caddy` workspace (and nothing else). It
  goes in `~/.secrets/tofu-ro.yaml`. Teams aren't available on every
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

In the Cloudflare dashboard:

1. **My Profile → API Tokens → Create Token.**
2. Next to the **Edit zone DNS** template, select **Use template**. It
   prefills the DNS permission row; you'll add the second row next.
3. **Token name:** something that says where it's used, e.g.
   `homelab-proxmox-core caddy dns-01`.
4. **Permissions:** each row is three dropdowns — group, item, access
   level. Make it exactly these two rows (use **+ Add more** for the
   second):

   | Group | Item | Access |
   | --- | --- | --- |
   | Zone | DNS | Edit |
   | Zone | Zone | Read |

5. **Zone Resources:** one row — **Include** · **Specific zone** ·
   `bcochofel.com`. Not *All zones*.
6. **Client IP Address Filtering** (optional): **Is in** your home public
   IP, since the token is only ever used from inside the LAN.
7. **TTL** (optional): leave empty for no expiry, or set an end date and
   plan to rotate.
8. **Continue to summary**, check it lists DNS *Edit* and Zone *Read*
   for `bcochofel.com` only, then **Create Token**.

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
  `~/.secrets/tofu-ro.yaml`. It's created now so the read-only file has
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
current directory, so create and edit these files from `~/.secrets`. The
first matching rule wins, so the read-only rule comes first.

```yaml
creation_rules:
  - path_regex: -ro\.yaml$
    age: <your-public-key>,<ai-agent-public-key>
  - path_regex: \.yaml$
    age: <your-public-key>
```

Each key **is** the environment variable name the tool reads, and values
must be flat strings (quote `"true"`). Create each file with
`cd ~/.secrets && sops <file>`:

`~/.secrets/packer.yaml`:

```yaml
PKR_VAR_proxmox_api_url: https://192.168.68.20:8006/api2/json
PKR_VAR_proxmox_node: pve1
PKR_VAR_proxmox_skip_tls_verify: "true"
PKR_VAR_proxmox_api_token_id: packer@pve!packer
PKR_VAR_proxmox_api_token_secret: <printed by pveum>
PKR_VAR_password_hash: <mkpasswd -m sha-512 '<password>' for the template user>
```

`~/.secrets/tofu.yaml`:

```yaml
TF_VAR_proxmox_api_token: bcochofel@pve!console=<secret printed by pveum>
TF_VAR_cipassword: <password for the cloud-init user on cloned VMs>
TF_TOKEN_app_terraform_io: <your HCP user token>
```

`~/.secrets/tofu-ro.yaml`:

```yaml
TF_VAR_proxmox_api_token: ai-agent@pve!ai-agent=<secret printed by pveum>
TF_VAR_cipassword: placeholder-not-a-real-password
TF_TOKEN_app_terraform_io: <ai-agent team token>
```

`TF_VAR_cipassword` gets a placeholder in the read-only file: plans run
against it, applies never do.

`PKR_VAR_password_hash` comes from the environment, so keep it out of
`packer/ubuntu-26.04/variables.auto.pkrvars.hcl`: a value in a varfile
takes precedence over `PKR_VAR_*`. The same goes for OpenTofu: never put
`proxmox_api_token` or `cipassword` in `terraform.tfvars`.

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

## 6. Running the pipeline

```bash
# Packer: build the template
cd packer/ubuntu-26.04
packer init .
sops exec-env ~/.secrets/packer.yaml 'packer build .'

# OpenTofu
cd ../../terraform
sops exec-env ~/.secrets/tofu-ro.yaml 'tofu init'
sops exec-env ~/.secrets/tofu-ro.yaml 'tofu plan -lock=false'   # read-only, as ai-agent
sops exec-env ~/.secrets/tofu.yaml 'tofu plan'                  # as console
sops exec-env ~/.secrets/tofu.yaml 'tofu apply'

# Ansible: no credentials to pass, it decrypts its own
cd ../ansible
ansible-playbook playbooks/site.yml
```

`sops exec-env` keeps the terminal attached, so `tofu apply`'s
confirmation prompt works as usual. The console `tofu plan` is the one to
review before applying. The read-only plan runs against a placeholder
`cipassword`, so it shows a change there even when nothing else changed.

## 7. Verify the boundary

Run these once after setup. A failure means a credential is wider than
intended.

```bash
env | grep -E 'PROXMOX|TF_VAR|TF_TOKEN|PKR_VAR'   # nothing: never exported

# The read-only identity can't write:
cd terraform
sops exec-env ~/.secrets/tofu-ro.yaml 'tofu apply'   # must fail before any change
                                                     # (HCP refuses the state lock);
                                                     # if it reaches the prompt, answer "no"

# The ai-agent age key opens only the read-only file:
SOPS_AGE_KEY_FILE=~/.config/sops/age/ai-agent.txt sops -d ~/.secrets/tofu.yaml     # must fail
SOPS_AGE_KEY_FILE=~/.config/sops/age/ai-agent.txt sops -d ~/.secrets/packer.yaml   # must fail
SOPS_AGE_KEY_FILE=~/.config/sops/age/ai-agent.txt sops -d ~/.secrets/tofu-ro.yaml >/dev/null && echo ok
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
