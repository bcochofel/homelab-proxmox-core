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

| You run | Identity | Proxmox API token | Proxmox role (what the token may do) | HCP Terraform token (state access) | How the credentials reach the command |
| --- | --- | --- | --- | --- | --- |
| `packer build` | `packer` | `packer@pve!packer` | `PackerBuild`: create a VM and turn it into a template | — | `packer_rw` |
| `tofu plan` / `tofu apply` | `console` | `bcochofel@pve!console` | `TofuApply`: clone the template and manage the VMs | your user token (read-write) | `tofu_rw` |
| `tofu plan -lock=false` (read-only check) | `ai-agent` | `ai-agent@pve!ai-agent` | `AiAgentRO`: read only | `ai-agent` team token (read-only) | `hl_ro` |
| `ansible-playbook` | you, over SSH | — (talks to the VMs, not to Proxmox) | — | — | Ansible decrypts its own secrets |
| Proxmox MCP server | `ai-agent` | `ai-agent@pve!ai-agent` | `AiAgentRO`: read only | — | `sops exec-env` (step 9) |
| GitHub / Terraform MCP servers | — (no Proxmox access) | — | — | — | `sops exec-env` (step 9) |

- **Proxmox API token:** the credential the tool presents to the Proxmox
  API, in the form `user@realm!token-name`.
- **Proxmox role:** a named set of privileges (e.g. `VM.Allocate`,
  `VM.Audit`). Step 1 creates the roles and attaches each to its token, so
  the role is what limits what that token can do.
- **HCP Terraform token:** access to the OpenTofu state stored in HCP
  Terraform (step 2), separate from Proxmox access.

`tofu plan` exists twice on purpose: as `console` it's the plan you review
before `tofu apply`; as `ai-agent` it proves a read-only identity can
plan, and is what an AI agent uses, since that identity can't apply.

Read and write credentials live in **separate SOPS files**, because SOPS
recipients are set per file:

| File | Holds | Encrypted to |
| --- | --- | --- |
| `~/.secrets/homelab-ro.yaml` | Proxmox endpoint/node, `ai-agent` token, HCP read-only token | you + the `ai-agent` age key |
| `~/.secrets/homelab.yaml` | Packer and console tokens, HCP read-write token, cloud-init password, template password hash | you only |
| `~/.secrets/mcp-<server>-ro.yaml` | One read-only credential per MCP server (step 9) | you + the `ai-agent` age key |
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
workspace `core-caddy`). OpenTofu authenticates to it with a token passed
as `TF_TOKEN_app_terraform_io`; you create two tokens here and store them
in step 5.

1. **Workspace:** in the organization, create a **CLI-driven** workspace
   named `core-caddy` (it must match `terraform/versions.tf`). Then
   *Settings → General → Execution Mode* → **Local**: Proxmox is LAN-only,
   so HCP's runners can't reach it, and HCP only stores state.
2. **Read-write token** (used by `tofu_rw` for `plan`/`apply`): your user
   API token, from *User settings → Tokens → Create an API token*.
   Store it as **`hcp_token`** in `~/.secrets/homelab.yaml`.
3. **Read-only token** (used by `hl_ro` for read-only `plan`):
   - *Settings → Teams*: create a team named `ai-agent`, with no
     organization-level permissions.
   - On the `core-caddy` workspace, *Settings → Team access*: give
     `ai-agent` **Read**, and nothing on any other workspace.
   - On the team's page, create a **team API token**.
   - Store it as **`hcp_ro_token`** in `~/.secrets/homelab-ro.yaml`.

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

- **Your key:** `~/.config/sops/age/keys.txt` (`chmod 600`). If you don't
  have one yet:

  ```bash
  age-keygen -o ~/.config/sops/age/keys.txt && chmod 600 ~/.config/sops/age/keys.txt
  ```

- **`ai-agent` key:** a separate key that only ever decrypts the
  read-only files (`~/.secrets/*-ro.yaml`). It's created now so the read-only file has
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
**current directory**, not the file's. Create and edit these files from
`~/.secrets` (`cd ~/.secrets && sops homelab.yaml`), or pass the config
explicitly (`sops --config ~/.secrets/.sops.yaml ~/.secrets/homelab.yaml`).
Running `sops ~/.secrets/homelab.yaml` from inside the repo picks up the
repo's `.sops.yaml` instead and fails with *no matching creation rules
found*.

```yaml
creation_rules:
  - path_regex: -ro\.yaml$
    age: <your-public-key>,<ai-agent-public-key>
  - path_regex: \.yaml$
    age: <your-public-key>
```

The first matching rule wins: every `*-ro.yaml` file (`homelab-ro.yaml`
and the MCP files in step 9) is readable by the `ai-agent` key, and
everything else only by yours.

Every key the two files need, where its value comes from, and which
helper (step 6) passes it to which tool:

| File | Key | Value | Passed as |
| --- | --- | --- | --- |
| `homelab-ro.yaml` | `proxmox_endpoint` | `https://<pve-host>:8006/` (trailing slash) | Packer API URL (`…api2/json` is appended) |
| `homelab-ro.yaml` | `proxmox_node` | node name, e.g. `pve1` | `PKR_VAR_proxmox_node` |
| `homelab-ro.yaml` | `ai_agent_token_id` | `ai-agent@pve!ai-agent` | `TF_VAR_proxmox_api_token` (with the secret) via `hl_ro` |
| `homelab-ro.yaml` | `ai_agent_token_secret` | printed by `pveum` (step 1) | same |
| `homelab-ro.yaml` | `hcp_ro_token` | team token (step 2.3) | `TF_TOKEN_app_terraform_io` via `hl_ro` |
| `homelab.yaml` | `packer_token_id` | `packer@pve!packer` | `PKR_VAR_proxmox_api_token_id` via `packer_rw` |
| `homelab.yaml` | `packer_token_secret` | printed by `pveum` (step 1) | `PKR_VAR_proxmox_api_token_secret` via `packer_rw` |
| `homelab.yaml` | `console_token_id` | `bcochofel@pve!console` | `TF_VAR_proxmox_api_token` (with the secret) via `tofu_rw` |
| `homelab.yaml` | `console_token_secret` | printed by `pveum` (step 1) | same |
| `homelab.yaml` | `hcp_token` | user token (step 2.2) | `TF_TOKEN_app_terraform_io` via `tofu_rw` |
| `homelab.yaml` | `cloudinit_password` | password for the cloud-init user on cloned VMs | `TF_VAR_cipassword` via `tofu_rw` |
| `homelab.yaml` | `password_hash` | `mkpasswd -m sha-512 '<password>'`, for the template's user | `PKR_VAR_password_hash` via `packer_rw` |

Key names must match exactly: the helpers in step 6 read them by name.

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

## 9. MCP servers for Claude Code

MCP servers let Claude Code read live state (Proxmox, GitHub, provider
docs) instead of guessing. Every server here is **read-only**, and that is
enforced by its credential, not by how it's normally used. They're added
with **user scope** (`--scope user`), so they're available in every
project, including `homelab-proxmox-workloads`, and stored in
`~/.claude.json` rather than in a repo.

Each server's token lives in its own SOPS file, and the server starts
through `sops exec-env`, so the token exists only in that server's process.
Never pass a token with `claude mcp add -e TOKEN=...`: that writes it in
plain text into `~/.claude.json`.

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

`~/.secrets/mcp-proxmox-ro.yaml` (keys are the server's environment
variables; quote every value):

```yaml
PROXMOX_HOST: "192.168.68.20"
PROXMOX_PORT: "8006"
PROXMOX_USER: "ai-agent@pve"
PROXMOX_TOKEN_NAME: "ai-agent"
PROXMOX_TOKEN_VALUE: "<ai-agent token secret, step 1>"
PROXMOX_VERIFY_TLS: "false"
PROXMOX_ALLOW_ELEVATED: "false"
```

`PROXMOX_ALLOW_ELEVATED: "false"` hides the server's write tools; the
`AiAgentRO` role is what actually makes writes impossible. This is the same
`ai-agent` token as in `homelab-ro.yaml`, so rotate both together.

```bash
claude mcp add proxmox --scope user -- \
  sops exec-env ~/.secrets/mcp-proxmox-ro.yaml \
  'node ~/.local/share/mcp-proxmox/index.js'
```

### GitHub

Create a **fine-grained personal access token** (*GitHub → Settings →
Developer settings → Fine-grained tokens → Generate new token*):

- **Resource owner:** `BCochofelHomelab`.
- **Repository access:** only `homelab-proxmox-core` and
  `homelab-proxmox-workloads`.
- **Repository permissions:** *Read-only* for Contents, Issues, Pull
  requests, Actions and Metadata. Nothing else, and no write access.

`~/.secrets/mcp-github-ro.yaml`:

```yaml
GITHUB_PERSONAL_ACCESS_TOKEN: "<fine-grained PAT>"
```

The server runs in Docker, in read-only mode, with only the toolsets this
work needs:

```bash
claude mcp add github --scope user -- \
  sops exec-env ~/.secrets/mcp-github-ro.yaml \
  'docker run -i --rm -e GITHUB_PERSONAL_ACCESS_TOKEN -e GITHUB_READ_ONLY=1 -e GITHUB_TOOLSETS=repos,issues,pull_requests,actions ghcr.io/github/github-mcp-server'
```

`-e GITHUB_PERSONAL_ACCESS_TOKEN` with no value copies it from the
environment `sops exec-env` set up. Pin the image to a version tag once
you've checked it.

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
