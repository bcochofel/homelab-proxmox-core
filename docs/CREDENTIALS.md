# Credentials

How to create every credential Packer, OpenTofu, Ansible and MCP need, where
each one is stored, and how it reaches the tool that uses it. Follow it
top to bottom on a clean Proxmox node before the first `packer build`.

The design follows Google's
[*AI engineering for reliable operations*](https://sre.google/resources/practices-and-processes/ai-engineering-reliable-operations/):
no ambient credentials, one identity per role, and an AI agent that can
only read. See the README's
[Why it's built this way](../README.md#why-its-built-this-way).

Written for **Proxmox VE 9.x**.

## The model

One identity per **role**, never one shared admin credential. There are
three Proxmox identities:

- **`packer`** — builds the VM template. Nothing else.
- **`terraform`** — changes infrastructure with OpenTofu (`tofu apply`), run by you.
- **`ai-agent`** — read-only: looks, never changes anything. Used by the
  AI agent's tools (the Proxmox MCP server). It has no access to the
  OpenTofu state, see step 2.

What each command runs as:

| You run | Identity | Proxmox API token | Proxmox role (what the token may do) | HCP Terraform token (state access) | Credentials come from |
| --- | --- | --- | --- | --- | --- |
| `mise run packer:build` | `packer` | `packer@pve!packer` | `PackerBuild`: create a VM and turn it into a template | — | `~/.secrets/homelab.yaml` |
| `mise run tofu:init` / `tofu:plan` / `tofu:apply` | `terraform` | `terraform@pve!terraform` | `TofuApply`: clone the template and manage the VMs | your user token (read-write) | `~/.secrets/homelab.yaml` |
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

Every plan runs as `terraform`, and you review it before `tofu:apply`.
The AI agent checks OpenTofu code without credentials (`tofu init
-backend=false`, `tofu validate`, linting) and never reads the state.

Read and write credentials live in **separate SOPS files**, because SOPS
recipients are set per file:

| File | Holds | Encrypted to |
| --- | --- | --- |
| `~/.secrets/homelab.yaml` | Read-write: Packer and `terraform` tokens, HCP read-write token, cloud-init password, template password hash | you only |
| `~/.secrets/homelab-ro.yaml` | Read-only: MCP credentials (incl. the `ai-agent` Proxmox token) | you + the `ai-agent` age key |
| `ansible/inventory/group_vars/<group>.sops.yaml` (committed) | Ansible-only secrets for this repo: Cloudflare token (`caddy`), Pihole password (`pihole`) | you only |

The split: credentials for non-Ansible tools, or shared across repos, go
in `~/.secrets/`; secrets only Ansible uses, for this repo only, go in
the encrypted `group_vars` file of the group that needs them, so no other
host ever sees them.

Nothing is ever exported into your shell. Each `mise run` task decrypts
one file with `sops exec-env` and passes it to one command, so the
credentials exist only in that process. Ansible decrypts its own secrets
at task time. The AI agent (Claude Code) only ever uses the `ai-agent` age key (step 6),
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
VM.Config.Network,VM.Config.Options,VM.Console,VM.GuestAgent.Audit,\
VM.PowerMgmt,Datastore.AllocateSpace,Datastore.AllocateTemplate,\
Datastore.Audit,Sys.Modify,SDN.Use"

# Clone the template into VMs and manage them: never builds a template.
pveum role add TofuApply -privs "VM.Allocate,VM.Audit,VM.Clone,\
VM.Config.CDROM,VM.Config.CPU,VM.Config.Cloudinit,VM.Config.Disk,\
VM.Config.HWType,VM.Config.Memory,VM.Config.Network,VM.Config.Options,\
VM.GuestAgent.Audit,VM.PowerMgmt,Datastore.Allocate,\
Datastore.AllocateSpace,Datastore.Audit,SDN.Use"

# Read-only: enough for `tofu plan` and investigation, nothing that changes
# state or runs anything inside a VM.
pveum role add AiAgentRO -privs "VM.Audit,VM.GuestAgent.Audit,\
Datastore.Audit,Sys.Audit,Pool.Audit,SDN.Audit"
```

If a role already exists, `pveum role modify <role> -privs "<full list>"`
replaces its privileges in place.

What each privilege is for: [`PACKER.md`](PACKER.md#proxmox-privileges)
(`PackerBuild`) and [`TERRAFORM.md`](TERRAFORM.md#proxmox-privileges)
(`TofuApply`).

**Guest-agent access stays read-only in every role.**
`VM.GuestAgent.Audit` only allows informational commands, such as reading
the VM's IP addresses, which `tofu plan` and Packer need. Never grant
`VM.GuestAgent.Unrestricted` (it allows running any program inside the
VM), `VM.GuestAgent.FileRead`, `VM.GuestAgent.FileWrite` or
`VM.GuestAgent.FileSystemMgmt` to any of these roles.

### Users and tokens

Tokens are created with **privilege separation** (`--privsep 1`): a token
gets only the permissions granted to the token itself, capped by its
user's. Each identity therefore gets two ACL entries, one for the user
and one for the token.

```bash
pveum user add packer@pve    --comment "Packer template builds (token only)"
pveum user add terraform@pve --comment "OpenTofu: tofu apply (token only)"
pveum user add ai-agent@pve  --comment "AI agent: read-only (token only)"

pveum user token add packer@pve    packer    --privsep 1 --comment "packer build"
pveum user token add terraform@pve terraform --privsep 1 --comment "tofu apply"
pveum user token add ai-agent@pve  ai-agent  --privsep 1 --comment "tofu plan / investigation"

pveum acl modify / --users  'packer@pve'              --roles PackerBuild
pveum acl modify / --tokens 'packer@pve!packer'       --roles PackerBuild
pveum acl modify / --users  'terraform@pve'           --roles TofuApply
pveum acl modify / --tokens 'terraform@pve!terraform' --roles TofuApply
pveum acl modify / --users  'ai-agent@pve'            --roles AiAgentRO
pveum acl modify / --tokens 'ai-agent@pve!ai-agent'   --roles AiAgentRO
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
pveum user token permissions terraform@pve terraform --path /
pveum user token permissions packer@pve packer --path /
```

## 2. HCP Terraform: workspace and tokens

State lives in HCP Terraform (organization `homelab-bcochofel-com`,
workspace `core-caddy`). OpenTofu authenticates to it with a token passed
as `TF_TOKEN_app_terraform_io`; you create one token here and store it in
step 5.

1. **Workspace:** in the organization, create a **CLI-driven** workspace
   named `core-caddy` (it must match `terraform/versions.tf`). Then
   *Settings → General → Execution Mode* → **Local**: Proxmox is LAN-only,
   so HCP's runners can't reach it, and HCP only stores state.
2. **Token** (used by `mise run tofu:init` / `tofu:plan` / `tofu:apply`):
   your user API token, from *User settings → Tokens → Create an API
   token*. Store it as **`TF_TOKEN_app_terraform_io`** in
   `~/.secrets/homelab.yaml`.
3. **No token for the AI agent.** A read-only state token needs a team
   with *Read* access to the workspace, and the HCP Terraform Free plan has
   no team management. Any token it can issue (user or organization) can
   also write or unlock state, which would break the read-only boundary,
   so the agent gets none and never plans against real state.
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
| Yours | `~/.config/sops/age/bcochofel.txt` | everything | you: the `mise run` tasks, `sops` |
| `ai-agent` | `~/.config/sops/age/ai-agent.txt` | `~/.secrets/homelab-ro.yaml` only | The AI agent (step 6) and its devcontainer |

**Your key is deliberately not at SOPS's default path**
(`~/.config/sops/age/keys.txt`). SOPS reads that file in every process,
on top of any key you point it at, so a key there would be available to
everything the AI agent runs, whatever `SOPS_AGE_KEY_FILE` says. Under its
own name, nothing finds it unless a command asks for it: the `mise run`
tasks pass it explicitly (see the bottom of `mise.toml`), and so do the
`sops` commands in this guide.

Create both:

```bash
mkdir -p ~/.config/sops/age && chmod 700 ~/.config/sops/age

age-keygen -o ~/.config/sops/age/bcochofel.txt
age-keygen -o ~/.config/sops/age/ai-agent.txt
chmod 600 ~/.config/sops/age/bcochofel.txt ~/.config/sops/age/ai-agent.txt
```

If you already have a key at the default path, keep it and just rename
it: `mv ~/.config/sops/age/keys.txt ~/.config/sops/age/bcochofel.txt`.
The files encrypted to it don't change.

`age-keygen` prints each public key as it creates it. To print one again
later:

```bash
age-keygen -y ~/.config/sops/age/bcochofel.txt  # your public key
age-keygen -y ~/.config/sops/age/ai-agent.txt   # ai-agent public key
```

Rules:

- Never put a key at `~/.config/sops/age/keys.txt`, and never add the
  `ai-agent` private key to your key file: each key stays a separate file
  that's used only when a command names it.
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
the file's. Create and edit these files from `~/.secrets`, or pass the
config explicitly (`sops --config ~/.secrets/.sops.yaml ...`). Running
`sops ~/.secrets/homelab.yaml` from inside the repo picks up the repo's
`.sops.yaml` instead and fails with *no matching creation rules found*.

Encrypting only needs the public keys, so creating a file works with plain
`sops`. Anything that decrypts (editing an existing file, `updatekeys`)
needs your key, which SOPS no longer finds on its own (step 4); name it:

```bash
ME=~/.config/sops/age/bcochofel.txt
```

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
# OpenTofu as terraform (mise run tofu:plan / tofu:apply)
TF_VAR_proxmox_api_token: "terraform@pve!terraform=<secret printed by pveum>"
TF_VAR_cipassword: "<password for the cloud-init user on cloned VMs>"
TF_TOKEN_app_terraform_io: "<your HCP user token, step 2>"
```

`~/.secrets/homelab-ro.yaml` (read-only, your key and the `ai-agent` key):

```yaml
# Proxmox MCP server (step 8)
PROXMOX_HOST: "192.168.68.20"
PROXMOX_PORT: "8006"
PROXMOX_USER: "ai-agent@pve"
PROXMOX_TOKEN_NAME: "ai-agent"
PROXMOX_TOKEN_VALUE: "<ai-agent secret printed by pveum, step 1>"
PROXMOX_VERIFY_TLS: "false"
PROXMOX_ALLOW_ELEVATED: "false"
# GitHub MCP server (step 8)
GITHUB_PERSONAL_ACCESS_TOKEN: "<read-only fine-grained PAT, step 8>"
```

Create each file **through `sops`**, so it's encrypted from the first
save and the plain values never touch the disk:

```bash
cd ~/.secrets                 # so ~/.secrets/.sops.yaml applies
sops homelab.yaml             # new file: opens $EDITOR with sample keys; replace them with yours, save, quit
sops homelab-ro.yaml          # same for the read-only file
chmod 600 homelab.yaml homelab-ro.yaml
```

On save, SOPS encrypts every value to the recipients of the matching
rule. Check both files are encrypted, and to whom:

```bash
sops filestatus homelab.yaml          # {"encrypted":true}
sops filestatus homelab-ro.yaml       # {"encrypted":true}
grep -A1 'recipient' homelab-ro.yaml  # your public key and the ai-agent one
grep -A1 'recipient' homelab.yaml     # your public key only
```

To change a value later, decrypt into the editor with your key, from
`~/.secrets`: `SOPS_AGE_KEY_FILE=$ME sops homelab.yaml`. It re-encrypts on
save. If you ever start
from a plain file instead, `sops encrypt --in-place <file>` encrypts it,
but the plain values were on disk until then.

Keep `password_hash` out of
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
mise run sops -- updatekeys ansible/inventory/group_vars/caddy.sops.yaml
mise run sops -- updatekeys ansible/inventory/group_vars/pihole.sops.yaml
```

`mise run sops -- <args>` is `sops` with your key, run from the current
directory; it works anywhere inside the repo. To edit an existing
inventory secret: `mise run sops -- ansible/inventory/group_vars/caddy.sops.yaml`.

If no current key can open them any more, delete and recreate them. Create
them from the repo root, where the repo's `.sops.yaml` applies; each opens
your editor on a new file and is encrypted on save, as above:

```bash
sops ansible/inventory/group_vars/caddy.sops.yaml
sops ansible/inventory/group_vars/pihole.sops.yaml

sops filestatus ansible/inventory/group_vars/caddy.sops.yaml    # {"encrypted":true}
sops filestatus ansible/inventory/group_vars/pihole.sops.yaml   # {"encrypted":true}
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

## 6. The AI agent uses only the `ai-agent` key

`.claude/settings.json` sets, for every command the AI agent runs:

- `SOPS_AGE_KEY_FILE` and `ANSIBLE_SOPS_AGE_KEYFILE` → the `ai-agent` key.

So, by construction:

- The MCP servers (step 8) work: the `ai-agent` key opens
  `homelab-ro.yaml`.
- `packer:build` and every `tofu:*` task fail: the `ai-agent` key can't
  open `homelab.yaml`. The ones that change anything are also denied to
  the AI agent outright.
- OpenTofu checks that need no credentials still work: `tofu init
  -backend=false`, `tofu validate`, `mise run lint`.
- Ansible can't decrypt the inventory secrets, and the AI agent's `ansible`
  and `ansible-playbook` commands always ask you first.

This holds only because your key isn't at SOPS's default path (step 4):
otherwise SOPS would use it for the agent's commands too.

It's still a **soft boundary**: the AI agent runs as your OS user, next
to your own key and `homelab.yaml`, and only the rules in
`.claude/settings.json` (deny reading your key file, every decrypting
`sops` command and every task that uses your key) keep it from them. The **hard boundary** is the
devcontainer, where those files are never mounted: see
[`DEVCONTAINER.md`](DEVCONTAINER.md#soft-and-hard-boundaries) for the
comparison and how to start it.

Adjust the key path in `.claude/settings.json` if your home directory
isn't `/home/bcochofel`.

## 7. Verify the credentials and the boundary

Before running anything that changes infrastructure, prove the setup works.
Three `mise` tasks cover it; each prints one `ok`/`FAIL` line per check and
never a secret value. Run them from the repo, on WSL:

```bash
mise run secrets:check    # each secret file opens with the right key, and only with it
mise run creds:check      # each credential authenticates (one read-only API call each)
mise run boundary:check   # the AI agent's boundary holds (checks 7.1-7.5)
```

Run them again whenever you change a role, a token, a secret file or a
`.sops.yaml` rule. `boundary:check` also runs in the devcontainer, where it
adds container-only checks ([`DEVCONTAINER.md`](DEVCONTAINER.md#prove-the-boundary)).
`secrets:check` and `creds:check` use your key, so they're yours only;
`boundary:check` uses only the `ai-agent` key, so the AI agent may run it
too.

The sections below explain what each check proves, how to run it by hand,
and what to do when it fails. Run the manual commands on WSL, as yourself,
from the **repo root**. They need `curl` and the `ai-agent` key from step
4.

### How the checks act as the agent

SOPS collects every age key it can find and tries each one: the file in
`SOPS_AGE_KEY_FILE` **and** whatever sits at the default
`~/.config/sops/age/keys.txt`. Your key isn't there (step 4), but to make
sure the checks test the `ai-agent` key and nothing else, they also give
SOPS an empty home directory, so the `ai-agent` key is the only one it
can see. Define this helper in the shell you run the checks from (it lasts
only for that shell):

```bash
AGENT_KEY=$HOME/.config/sops/age/ai-agent.txt
as_agent() { HOME=$(mktemp -d) SOPS_AGE_KEY_FILE=$AGENT_KEY "$@"; }
```

`AGENT_KEY` is set first, as a full path: inside `as_agent` a `~` would
already point at the empty home and name a key file that doesn't exist.

Every check below that involves SOPS runs through it.

### 7.1. Nothing is exported into your shell

```bash
env | grep -E 'PKR_VAR|TF_VAR|TF_TOKEN|PROXMOX|GITHUB_PERSONAL'
```

**Expect:** no output. Credentials only exist inside a `mise run` task
or an MCP server process. Any output means something exports them (an
old `.envrc`, `~/.zshrc`, a profile script): remove it.

### 7.2. The agent's key opens the read-only file

```bash
as_agent sops -d ~/.secrets/homelab-ro.yaml >/dev/null && echo ok
```

**Expect:** `ok`. If it fails, the `ai-agent` public key isn't a
recipient of `homelab-ro.yaml`: fix the rule in `~/.secrets/.sops.yaml`,
then `cd ~/.secrets && SOPS_AGE_KEY_FILE=~/.config/sops/age/bcochofel.txt sops updatekeys homelab-ro.yaml` (step 5).

### 7.3. The agent's key opens nothing else

```bash
for f in ~/.secrets/homelab.yaml \
         ansible/inventory/group_vars/caddy.sops.yaml \
         ansible/inventory/group_vars/pihole.sops.yaml; do
  as_agent sops -d "$f" >/dev/null 2>&1 && echo "OPENS (bad): $f" || echo "refused (good): $f"
done
```

**Expect:** `refused (good)` for all three. (Run without the
`>/dev/null 2>&1`, SOPS shows why: it lists the public `age1...` keys the
file is encrypted to, none of which it holds, and ends with *Failed to get
the data key required to decrypt the SOPS file*. Nothing secret is
printed.) If any of them succeeds, that file was encrypted
to the `ai-agent` key: remove it from the matching `.sops.yaml` rule and
re-encrypt it with your key and `updatekeys` (step 5). The recipients are public, so you
can also list them: `grep -A1 recipient <file>` shows only your public
key.

### 7.4. The read-only file holds no OpenTofu or HCP credential

```bash
as_agent sops exec-env ~/.secrets/homelab-ro.yaml 'env | grep -c "^TF_"'
```

**Expect:** `0`, followed by `exit status 1` (that's `grep -c`'s exit
code when it counts nothing, not an error). `sops exec-env` runs the
command with the file's keys as environment variables, and `grep -c`
prints only how many start with `TF_`, never their values. Anything above `0` means a `TF_VAR_*` or
`TF_TOKEN_*` key is still in the file (step 2 explains why the agent gets
none): remove it with `cd ~/.secrets && SOPS_AGE_KEY_FILE=~/.config/sops/age/bcochofel.txt sops homelab-ro.yaml`.

### 7.5. The `ai-agent` Proxmox token can't write

```bash
as_agent sops exec-env ~/.secrets/homelab-ro.yaml \
  'curl -sk -o /dev/null -w "%{http_code}\n" -X POST -d poolid=boundary-test \
   -H "Authorization: PVEAPIToken=$PROXMOX_USER!$PROXMOX_TOKEN_NAME=$PROXMOX_TOKEN_VALUE" \
   https://$PROXMOX_HOST:$PROXMOX_PORT/api2/json/pools'
```

This asks the Proxmox API, as `ai-agent@pve!ai-agent`, to create a
resource pool: a harmless write that needs `Pool.Allocate`, which
`AiAgentRO` doesn't have. The single quotes matter: the `$PROXMOX_*`
variables are expanded inside `sops exec-env`, from the file, not by your
shell. `curl` prints only the HTTP status.

**Expect:** `403` (permission denied).

- `200`: the token can write. Delete the `boundary-test` pool
  (*Datacenter → Permissions → Pools*) and fix the `AiAgentRO` role and
  its ACLs (step 1).
- `401`: the token itself is wrong. Check `PROXMOX_USER`,
  `PROXMOX_TOKEN_NAME` and `PROXMOX_TOKEN_VALUE` in `homelab-ro.yaml`.
- `000`: Proxmox wasn't reached. Check `PROXMOX_HOST` and
  `PROXMOX_PORT`.

### 7.6. Every credential authenticates

`mise run creds:check` makes one read-only API call with each credential,
and checks that the values with no API to call are set:

| Credential | File | Call | Expect |
| --- | --- | --- | --- |
| `packer@pve!packer` | `homelab.yaml` | Proxmox `GET /version` | `200` |
| `terraform@pve!terraform` | `homelab.yaml` | Proxmox `GET /version` | `200` |
| HCP token | `homelab.yaml` | read workspace `homelab-bcochofel-com/core-caddy` | `200` |
| `ai-agent@pve!ai-agent` | `homelab-ro.yaml` (`ai-agent` key only) | Proxmox `GET /version` | `200` |
| GitHub PAT | `homelab-ro.yaml` (`ai-agent` key only) | read both homelab repos | `200` |
| Cloudflare token | `caddy.sops.yaml` | look up zone `bcochofel.com` | `200` |
| `PKR_VAR_password_hash`, `TF_VAR_cipassword`, `pihole_webpassword` | | set and not empty | `ok` |

Secrets reach `curl` through standard input (`-H @-`), never as
command-line arguments, so they don't show up in the process list. If a
line fails:

- `401`: the credential is wrong or revoked: recreate it (steps 1–3, or
  step 8 for the PAT) and update the file with your key.
- `403` or `404`: it authenticates but can't see that resource: check its
  ACL, team access, zone or repository access.
- `000`: the service wasn't reached: check the host and port values.

## 8. MCP servers for the AI agent

MCP servers let the AI agent read live state (Proxmox, GitHub, provider
docs) instead of guessing. Every server here is **read-only**, enforced by
its credential, not by how it's normally used.

| Server | What it gives the AI agent | Credential |
| --- | --- | --- |
| Proxmox | VMs, nodes, storage and cluster state | `ai-agent@pve!ai-agent` (step 1), `AiAgentRO` role |
| GitHub | Repos, issues, pull requests and Actions runs for both homelab repos | Fine-grained PAT, read-only |
| Terraform | Provider and module docs from the public registry (e.g. `bpg/proxmox`), so resources aren't written from memory | None |

MCP servers for the workloads themselves belong to
`homelab-proxmox-workloads`; nothing in this repo needs them.

### How they're configured

The servers are registered in the repo's **`.mcp.json`** (project scope),
so the same configuration works on WSL and in the devcontainer
([`DEVCONTAINER.md`](DEVCONTAINER.md)). It holds no secrets:

- The Proxmox and GitHub servers start through
  `sops exec-env ${HOME}/.secrets/homelab-ro.yaml`, with
  `SOPS_AGE_KEY_FILE` set to the `ai-agent` key (a path, not a secret).
  Their tokens exist only in each server's process.
- The Terraform server needs no credential.
- Every binary is pinned: the GitHub and Terraform servers in `mise.toml`
  (installed by `mise install`, checksums in `mise.lock`), the Proxmox
  server by `mise run mcp:install` (a reviewed commit).

Never add a token to `.mcp.json` or to `claude mcp add -e TOKEN=...`:
both store it in plain text.

### Setup on WSL

The devcontainer does all of this itself when it's created. On WSL:

1. Create the GitHub token below and add it to `homelab-ro.yaml`.
2. Install the Proxmox server: `mise run mcp:install`.
3. Start Claude Code in the repo and approve the three project MCP servers
   when it asks (or later with `/mcp`).

If you added these servers with `claude mcp add --scope user` before,
remove them (`claude mcp remove <name> --scope user`) so only the
project's `.mcp.json` defines them.

### Proxmox

`gilby125/mcp-proxmox` (Node.js) isn't published as a package, so
`mise run mcp:install` clones it into `~/.local/share/mcp-proxmox` at the
commit pinned in `mise.toml`. Review the upstream diff before bumping that
commit.

It reads the `PROXMOX_*` keys from `homelab-ro.yaml`.
`PROXMOX_ALLOW_ELEVATED: "false"` hides its write tools; the `AiAgentRO`
role is what actually makes writes impossible.

### GitHub

Create a **fine-grained personal access token** (*GitHub → Settings →
Developer settings → Fine-grained tokens → Generate new token*) and store
it as `GITHUB_PERSONAL_ACCESS_TOKEN` in `homelab-ro.yaml`:

- **Resource owner:** `BCochofelHomelab`.
- **Repository access:** only `homelab-proxmox-core` and
  `homelab-proxmox-workloads`.
- **Repository permissions:** *Read-only* for Contents, Issues, Pull
  requests, Actions and Metadata. Nothing else, and no write access.

The server (`github-mcp-server`, pinned in `mise.toml`) runs with
`--read-only` and only the toolsets this work needs
(`repos,issues,pull_requests,actions`).

### Terraform (registry docs)

`terraform-mcp-server`, pinned in `mise.toml`, runs with
`--toolsets=registry`: public-registry docs only. Don't give it
`TFE_TOKEN`, which would open HCP Terraform workspaces and state.

### Check them

```bash
claude mcp list   # proxmox, github and terraform show "Connected"
```

Then prove each one is read-only by asking the AI agent, in a session, to
do something it must not be able to do. Each request must fail:

- Proxmox: stop or snapshot a VM (Proxmox returns 403).
- GitHub: comment on an issue (no write tools exist).
- Terraform: list HCP Terraform workspaces (no tools for that).
