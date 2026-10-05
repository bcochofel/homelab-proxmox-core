# Credentials

How to create every credential Packer, OpenTofu, Ansible and MCP need, where
each one is stored, and how it reaches the tool that uses it. Follow it
top to bottom on a clean Proxmox node before the first `packer build`.

Written for **Proxmox VE 8.x** (see [Proxmox VE 9](#proxmox-ve-9) for
what changes after an upgrade).

## The model

One identity per **role**, never one shared admin credential. There are
three Proxmox identities:

- **`packer`** — builds the VM template. Nothing else.
- **`console`** — you, changing infrastructure with OpenTofu.
- **`ai-agent`** — read-only: looks, never changes anything. Used by the
  read-only `tofu plan` and by the AI agent's tools.

What each command runs as:

| You run | Identity | Proxmox API token | Proxmox role (what the token may do) | HCP Terraform token (state access) | Credentials come from |
| --- | --- | --- | --- | --- | --- |
| `mise run packer:build` | `packer` | `packer@pve!packer` | `PackerBuild`: create a VM and turn it into a template | — | `~/.secrets/homelab.yaml` |
| `mise run tofu:plan` / `tofu:apply` | `console` | `bcochofel@pve!console` | `TofuApply`: clone the template and manage the VMs | your user token (read-write) | `~/.secrets/homelab.yaml` |
| `mise run tofu:plan-ro` (read-only check; also what the AI agent runs) | `ai-agent` | `ai-agent@pve!ai-agent` | `AiAgentRO`: read only | `ai-agent` team token (read-only) | `~/.secrets/homelab-ro.yaml` |
| `ansible-playbook` | you, over SSH | — (talks to the VMs, not to Proxmox) | — | — | `group_vars/*.sops.yaml`, decrypted by Ansible |
| Proxmox / GitHub MCP servers | `ai-agent` | `ai-agent@pve!ai-agent` (Proxmox) | `AiAgentRO`: read only | — | `~/.secrets/homelab-ro.yaml` |
| Terraform MCP server | — | — | — | — | none needed |

- **Proxmox API token:** the credential the tool presents to the Proxmox
  API, in the form `user@realm!token-name`.
- **Proxmox role:** a named set of privileges (e.g. `VM.Allocate`,
  `VM.Audit`). Step 1 creates the roles and attaches each to its token, so
  the role is what limits what that token can do.
- **HCP Terraform token:** access to the OpenTofu state stored in HCP
  Terraform (step 2), separate from Proxmox access.

The plan exists twice on purpose: `tofu:plan` (as `console`) is the one
you review before `tofu:apply`; `tofu:plan-ro` (as `ai-agent`) is what an
AI agent runs, and proves a read-only identity can plan without being able
to apply.

Read and write credentials live in **separate SOPS files**, because SOPS
recipients are set per file:

| File | Holds | Encrypted to |
| --- | --- | --- |
| `~/.secrets/homelab.yaml` | Read-write: Packer and console tokens, HCP read-write token, cloud-init password, template password hash | you only |
| `~/.secrets/homelab-ro.yaml` | Read-only: `ai-agent` token, HCP read-only token, MCP credentials | you + the `ai-agent` age key |
| `ansible/inventory/group_vars/<group>.sops.yaml` (committed) | Ansible-only secrets for this repo: Cloudflare token (`caddy`), Pihole password (`pihole`) | you only |

The split: credentials for non-Ansible tools, or shared across repos, go
in `~/.secrets/`; secrets only Ansible uses, for this repo only, go in
the encrypted `group_vars` file of the group that needs them, so no other
host ever sees them.

Nothing is ever exported into your shell. Each `mise run` task decrypts
one file with `sops exec-env` and passes it to one command, so the
credentials exist only in that process. Ansible decrypts its own secrets
at task time. Claude Code only ever uses the `ai-agent` age key (step 7),
so it can open the read-only file and nothing else.

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
workspace `core-caddy`). OpenTofu authenticates to it with a token passed
as `TF_TOKEN_app_terraform_io`; you create two tokens here and store them
in step 5.

1. **Workspace:** in the organization, create a **CLI-driven** workspace
   named `core-caddy` (it must match `terraform/versions.tf`). Then
   *Settings → General → Execution Mode* → **Local**: Proxmox is LAN-only,
   so HCP's runners can't reach it, and HCP only stores state.
2. **Read-write token** (used by `mise run tofu:plan` / `tofu:apply`): your
   user API token, from *User settings → Tokens → Create an API token*.
   Store it as **`TF_TOKEN_app_terraform_io`** in `~/.secrets/homelab.yaml`.
3. **Read-only token** (used by `mise run tofu:init` / `tofu:plan-ro`):
   - *Settings → Teams*: create a team named `ai-agent`, with no
     organization-level permissions.
   - On the `core-caddy` workspace, *Settings → Team access*: give
     `ai-agent` **Read**, and nothing on any other workspace.
   - On the team's page, create a **team API token**.
   - Store it as **`TF_TOKEN_app_terraform_io`** in
     `~/.secrets/homelab-ro.yaml`.

   Teams aren't available on every HCP plan, so check yours. Read access
   can't lock state, which is why read-only plans run with `-lock=false`.
4. Remove `~/.terraform.d/credentials.tfrc.json` if `tofu login` (or
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

Every secret file is encrypted with [SOPS](https://github.com/getsops/sops)
to one or more [age](https://github.com/FiloSottile/age) keys. Each key is
a pair: the **public** key (`age1...`) goes into SOPS configuration and
can be shared; the **private** key stays in a file only you control.
There are exactly two:

| Key | Private key file | Can decrypt | Used by |
| --- | --- | --- | --- |
| Yours | `~/.config/sops/age/keys.txt` | everything | you: `sops`, the `mise run` tasks, Ansible |
| `ai-agent` | `~/.config/sops/age/ai-agent.txt` | `~/.secrets/homelab-ro.yaml` only | Claude Code (step 7) and its devcontainer |

Create both (skip the first if you already have a key):

```bash
mkdir -p ~/.config/sops/age && chmod 700 ~/.config/sops/age

age-keygen -o ~/.config/sops/age/keys.txt
age-keygen -o ~/.config/sops/age/ai-agent.txt
chmod 600 ~/.config/sops/age/keys.txt ~/.config/sops/age/ai-agent.txt
```

`age-keygen` prints each public key as it creates it. To print one again
later:

```bash
age-keygen -y ~/.config/sops/age/keys.txt       # your public key
age-keygen -y ~/.config/sops/age/ai-agent.txt   # ai-agent public key
```

Rules:

- SOPS finds your key automatically at `~/.config/sops/age/keys.txt`.
  Never add the `ai-agent` private key to that file: it must stay a
  separate key that Claude Code can be given on its own.
- Neither private key ever goes into a repository. Back both up somewhere
  safe (e.g. a password manager): without them nothing can be decrypted,
  and a lost key means recreating every secret.

## 5. Secret files

```bash
mkdir -p ~/.secrets && chmod 700 ~/.secrets
```

`~/.secrets/.sops.yaml`:

```yaml
creation_rules:
  - path_regex: homelab-ro\.yaml$
    age: <your-public-key>,<ai-agent-public-key>
  - path_regex: homelab\.yaml$
    age: <your-public-key>
```

SOPS looks for its config starting from the **current directory**, not
the file's. Create and edit these files from `~/.secrets`
(`cd ~/.secrets && sops homelab.yaml`), or pass the config explicitly
(`sops --config ~/.secrets/.sops.yaml ~/.secrets/homelab.yaml`). Running
`sops ~/.secrets/homelab.yaml` from inside the repo picks up the repo's
`.sops.yaml` instead and fails with *no matching creation rules found*.

Each key **is** the environment variable name the tool reads, because
`sops exec-env` passes the file's keys to the command as environment
variables. Quote every value.

`~/.secrets/homelab.yaml` (read-write, your key only):

```yaml
# Packer (mise run packer:build)
PKR_VAR_proxmox_api_url: "https://192.168.68.20:8006/api2/json"
PKR_VAR_proxmox_node: "pve1"
PKR_VAR_proxmox_skip_tls_verify: "true"
PKR_VAR_proxmox_api_token_id: "packer@pve!packer"
PKR_VAR_proxmox_api_token_secret: "<printed by pveum, step 1>"
PKR_VAR_password_hash: "<mkpasswd -m sha-512 '<password>', the template user>"
# OpenTofu as console (mise run tofu:plan / tofu:apply)
TF_VAR_proxmox_api_token: "bcochofel@pve!console=<secret printed by pveum>"
TF_VAR_cipassword: "<password for the cloud-init user on cloned VMs>"
TF_TOKEN_app_terraform_io: "<your HCP user token, step 2>"
```

`~/.secrets/homelab-ro.yaml` (read-only, your key and the `ai-agent` key):

```yaml
# OpenTofu as ai-agent (mise run tofu:init / tofu:plan-ro)
TF_VAR_proxmox_api_token: "ai-agent@pve!ai-agent=<secret printed by pveum>"
TF_VAR_cipassword: "placeholder-not-a-real-password"
TF_TOKEN_app_terraform_io: "<ai-agent team token, step 2>"
# Proxmox MCP server (step 9)
PROXMOX_HOST: "192.168.68.20"
PROXMOX_PORT: "8006"
PROXMOX_USER: "ai-agent@pve"
PROXMOX_TOKEN_NAME: "ai-agent"
PROXMOX_TOKEN_VALUE: "<the same ai-agent secret>"
PROXMOX_VERIFY_TLS: "false"
PROXMOX_ALLOW_ELEVATED: "false"
# GitHub MCP server (step 9)
GITHUB_PERSONAL_ACCESS_TOKEN: "<read-only fine-grained PAT, step 9>"
```

`TF_VAR_cipassword` gets a placeholder in the read-only file: plans run
against it, applies never do. Keep `password_hash` out of
`packer/ubuntu-26.04/variables.auto.pkrvars.hcl`, and `proxmox_api_token`
and `cipassword` out of `terraform.tfvars`: a value in a varfile takes
precedence over the environment.

Ansible's secrets are inventory variables, so each lives next to the rest
of its group's variables, encrypted to **your key only**. The repo's own
`.sops.yaml` (at the repo root, committed) says so:

```yaml
---
creation_rules:
  - path_regex: \.sops\.ya?ml$
    age: <your-public-key>
```

It holds only your **public** key, so committing it is safe. If you
created a new key in step 4, put its public key there before creating the
files below. To change recipients of files that already exist (a new key,
or adding CI later), edit `.sops.yaml` and re-encrypt them in place with a
key that can still open them:

```bash
sops updatekeys ansible/inventory/group_vars/caddy.sops.yaml
sops updatekeys ansible/inventory/group_vars/pihole.sops.yaml
```

If no current key can open them any more, delete and recreate them. Create
them from the repo root, where the repo's `.sops.yaml` applies:

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

The `community.sops` vars plugin (`ansible/ansible.cfg`) decrypts them only
while a task runs (`vars_stage = task`), so `ansible-lint`,
`--syntax-check` and `ansible-inventory` never decrypt them. They're never
encrypted to the `ai-agent` key: a service password or API token has no
read-only form, and even `ansible-playbook --check` decrypts them to render
templates. The AI agent's Ansible work stops at linting, syntax checks and
reading playbooks.

Back up `~/.secrets/` and both age keys somewhere safe. Without the age
keys, none of these files can be decrypted.

## 6. Running the pipeline

Each credentialed command is a `mise` task that wraps one command in
`sops exec-env` (see the bottom of `mise.toml`). Run them from anywhere in
the repo:

```bash
mise run packer:build    # packer init + build, as packer
mise run tofu:init       # one time
mise run tofu:plan-ro    # optional read-only check, as ai-agent
mise run tofu:plan       # as console: review this one
mise run tofu:apply      # as console

cd ansible && ansible-playbook playbooks/site.yml   # no credentials to pass
```

The read-only plan runs against a placeholder `cipassword`, so it shows a
change there even when nothing else changed. The tasks take no extra
arguments; for a one-off flag, run the underlying command yourself, e.g.
`cd terraform && sops exec-env ~/.secrets/homelab.yaml 'tofu plan -target=module.caddy'`.

## 7. Claude Code uses only the `ai-agent` key

`.claude/settings.json` sets, for every command Claude Code runs:

- `SOPS_AGE_KEY_FILE` and `ANSIBLE_SOPS_AGE_KEYFILE` → the `ai-agent` key.

So, by construction:

- `mise run tofu:plan-ro` works: the `ai-agent` key opens
  `homelab-ro.yaml`.
- `packer:build`, `tofu:plan` and `tofu:apply` fail: the `ai-agent` key
  can't open `homelab.yaml`. They're also denied to Claude Code outright.
- Ansible can't decrypt the inventory secrets, and Claude Code's `ansible`
  and `ansible-playbook` commands always ask you first.
- The MCP servers (step 9) start with the same setting, so they can open
  only `homelab-ro.yaml`.

This is a soft boundary: Claude Code still runs as your OS user, and only
the deny rules keep it from reading your own key. The hard boundary is a
devcontainer that holds only the `ai-agent` key (`TODO-SRE-AI.md`, A6).

Adjust the key path in `.claude/settings.json` if your home directory
isn't `/home/bcochofel`.

## 8. Verify the boundary

Run these once after setup. A failure means a credential is wider than
intended.

```bash
env | grep -E 'PKR_VAR|TF_VAR|TF_TOKEN|PROXMOX|GITHUB_PERSONAL'   # nothing: never exported

AGENT=~/.config/sops/age/ai-agent.txt
SOPS_AGE_KEY_FILE=$AGENT sops -d ~/.secrets/homelab-ro.yaml >/dev/null && echo ok   # ok
SOPS_AGE_KEY_FILE=$AGENT sops -d ~/.secrets/homelab.yaml                            # must fail
SOPS_AGE_KEY_FILE=$AGENT sops -d ansible/inventory/group_vars/caddy.sops.yaml      # must fail

# The read-only identity can't write: must fail before any change
# (HCP refuses the state lock); if it ever reaches the prompt, answer "no".
cd terraform && sops exec-env ~/.secrets/homelab-ro.yaml 'tofu apply'
```

## 9. MCP servers for Claude Code

MCP servers let Claude Code read live state (Proxmox, GitHub, provider
docs) instead of guessing. Every server here is **read-only**, enforced by
its credential, not by how it's normally used. They're added with **user
scope** (`--scope user`), so they're available in every project, including
`homelab-proxmox-workloads`, and stored in `~/.claude.json` rather than in
a repo.

Their credentials are in `~/.secrets/homelab-ro.yaml` (step 5), and each
server starts through `sops exec-env`, so a token exists only in that
server's process. Never pass a token with `claude mcp add -e TOKEN=...`:
that writes it in plain text into `~/.claude.json`.

| Server | What it gives Claude Code | Credential |
| --- | --- | --- |
| Proxmox | VMs, nodes, storage and cluster state | `ai-agent@pve!ai-agent` (step 1), `AiAgentRO` role |
| GitHub | Repos, issues, pull requests and Actions runs for both homelab repos | Fine-grained PAT, read-only |
| Terraform | Provider and module docs from the public registry (e.g. `bpg/proxmox`), so resources aren't written from memory | None |

The Elastic, Kubernetes and ArgoCD MCP servers belong to
`homelab-proxmox-workloads`, which runs those services; nothing in this
repo needs them.

### Proxmox

Install the server (Node.js) outside any repo, pinned to a commit you've
reviewed:

```bash
git clone https://github.com/gilby125/mcp-proxmox ~/.local/share/mcp-proxmox
cd ~/.local/share/mcp-proxmox && git checkout <reviewed-commit> && npm ci
```

It reads the `PROXMOX_*` keys from `homelab-ro.yaml`.
`PROXMOX_ALLOW_ELEVATED: "false"` hides its write tools; the `AiAgentRO`
role is what actually makes writes impossible.

```bash
claude mcp add proxmox --scope user -- \
  sops exec-env ~/.secrets/homelab-ro.yaml \
  'node ~/.local/share/mcp-proxmox/index.js'
```

### GitHub

Create a **fine-grained personal access token** (*GitHub → Settings →
Developer settings → Fine-grained tokens → Generate new token*) and store
it as `GITHUB_PERSONAL_ACCESS_TOKEN` in `homelab-ro.yaml`:

- **Resource owner:** `BCochofelHomelab`.
- **Repository access:** only `homelab-proxmox-core` and
  `homelab-proxmox-workloads`.
- **Repository permissions:** *Read-only* for Contents, Issues, Pull
  requests, Actions and Metadata. Nothing else, and no write access.

The server runs in Docker, read-only, with only the toolsets this work
needs:

```bash
claude mcp add github --scope user -- \
  sops exec-env ~/.secrets/homelab-ro.yaml \
  'docker run -i --rm -e GITHUB_PERSONAL_ACCESS_TOKEN -e GITHUB_READ_ONLY=1 -e GITHUB_TOOLSETS=repos,issues,pull_requests,actions ghcr.io/github/github-mcp-server'
```

`-e GITHUB_PERSONAL_ACCESS_TOKEN` with no value copies only that variable
into the container. Pin the image to a version tag once you've checked it.

### Terraform (registry docs)

No credential: only the public-registry tools are enabled. Don't set
`TFE_TOKEN`, which would give it access to HCP Terraform workspaces and
state.

```bash
claude mcp add terraform --scope user -- \
  docker run -i --rm hashicorp/terraform-mcp-server:<version> --toolsets=registry
```

### Check them

```bash
claude mcp list   # proxmox, github and terraform show "Connected"
```

Then prove each one is read-only by asking Claude Code, in a session, to
do something it must not be able to do. Each request must fail:

- Proxmox: stop or snapshot a VM (Proxmox returns 403).
- GitHub: comment on an issue (no write tools exist).
- Terraform: list HCP Terraform workspaces (no tools for that).

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
