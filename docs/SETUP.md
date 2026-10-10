# Setup

How to build this homelab from nothing, or rebuild it after losing
everything, the GitHub organization included, and end up exactly where it
is today. This page is day 0 and day 1: everything in order, each stage
closed by its check. Day 2 (adding a proxied site, testing DNS) is in the
[README](../README.md).

## How to use this page

- **Follow the stages in order.** Each one relies on the ones before it,
  and ends with a check that must pass before you go on.
- **Stages 7 and 8 are optional.** Without them you have the homelab
  (Caddy, CoreDNS, Pi-hole) but no AI agent and no CI dry-run.
- **The credential procedures** live in [`CREDENTIALS.md`](CREDENTIALS.md);
  this page says when to do each step. Start by reading its
  [secret tiers](CREDENTIALS.md#secret-tiers): who can read what, and why.
- **This page is the record** of everything configured by hand (GitHub,
  Proxmox, HCP, Cloudflare). Change a setting, change it here too.

## Stage 1. Workstation

Ubuntu, under WSL2 or native; never PowerShell.

1. **mise**, at the version `.devcontainer/post-create.sh` pins (run from
   a clone of the repo):

   ```bash
   curl -fsSL https://mise.run \
     | MISE_VERSION="$(sed -n 's/.*MISE_VERSION=\([^ ]*\).*/\1/p' .devcontainer/post-create.sh)" sh
   echo 'eval "$(~/.local/bin/mise activate zsh)"' >> ~/.zshrc   # or bash / ~/.bashrc
   ```

   Start a new shell. Activation is the only line the repo needs in your
   shell profile: it puts the pinned tools first on `PATH` inside the repo,
   activates `.venv/`, and exports no secrets.
2. **The toolchain**, from the repo root:

   ```bash
   mise trust && mise install   # every pinned tool, .venv/ with Ansible, git hooks
   mise run doctor              # must end with "No problems found"
   ```

3. **Your SSH key**, `~/.ssh/id_ed25519`: Packer builds with it, and it's
   the key on every VM and Proxmox node (`sshkeys`, `ssh_authorized_keys`).
4. **The GitHub CLI**, as you, once stage 2 exists:

   ```bash
   gh auth login --hostname github.com --git-protocol ssh --web
   gh auth refresh --scopes admin:org   # the organization checks below need it
   gh auth status                        # account bcochofel
   ```

   The login lives in `~/.config/gh/hosts.yml`. The AI agent never uses it:
   on WSL `.claude/settings.json` denies it `gh auth` and every `gh` write,
   and in the devcontainer `gh` is the machine user's (stage 7).
5. **For stage 7 only:** Docker Engine inside WSL, and VS Code with the
   *WSL* and *Dev Containers* extensions.

**Check:** `mise run doctor` shows no problems, and every tool at the
version `mise.toml` pins.

## Stage 2. GitHub organization

Configured by hand in GitHub's web UI; nothing applies it. The
organization is on the **Free** plan, which is why the rulesets are per
repository (organization rulesets need Team).

### Organization

Create the organization `BCochofelHomelab` (Free), owned by `bcochofel`.
Then, in its *Settings*:

| Where | Setting | Value | Why |
| --- | --- | --- | --- |
| Member privileges | Base permissions | Read | Repository access comes only from teams. |
| Member privileges | Repository creation | Off | The machine user can't create repositories. |
| Member privileges | Allow members to create teams | Off | Teams, and what they reach, are an owner's decision. |
| Authentication security | Require two-factor authentication | On | Every member, the machine user included. |
| Personal access tokens | Fine-grained tokens | Allowed, owner approval required | The machine user's token needs your approval before it works. |

### Repositories

Two **public** repositories, `homelab-proxmox-core` and
`homelab-proxmox-workloads`, default branch `main`. Rebuilding: create
each one **empty** (no README, licence or `.gitignore`), then push it from
your clone, tags included:

```bash
git remote set-url origin git@github.com:BCochofelHomelab/homelab-proxmox-core.git
git push -u origin main --tags
```

*Settings → General*, in both:

- **Pull requests:** merge commits, squash and rebase merging allowed
  (`protected-default` requires linear history, so a merge commit is
  refused anyway); **Automatically delete head branches** on.

### Teams

Both *closed* (visible to members), both with **Write** on both
repositories:

| Team | Members | Purpose |
| --- | --- | --- |
| `sre-team` | `bcochofel` (maintainer), `bcochofel-ai-agent` (stage 7) | Who pushes branches and opens pull requests. |
| `sre-lead` | `bcochofel` (maintainer) | Who reviews: the code owner of every file. |

No one gets a direct grant on a repository. `sre-lead` needs Write: GitHub
ignores a CODEOWNERS team without it. The machine user must **never** be
in `sre-lead`: its approval would count as a code owner's.

### CODEOWNERS

`.github/CODEOWNERS`, in both repositories, already committed:

```text
* @BCochofelHomelab/sre-lead
```

Every file, `CODEOWNERS` included. Never assign a path to `sre-team`: the
machine user is in it. CODEOWNERS doesn't stop anyone pushing a branch; it
decides whose approval a pull request needs to reach `main`.

### Rulesets

The same two in each repository, *Settings → Rules → Rulesets*, both
*Active*.

**`protected-default`**, target the default branch:

| Rule | Setting |
| --- | --- |
| Restrict deletions | On |
| Block force pushes | On |
| Require linear history | On |
| Require a pull request before merging | On |
| Required approvals | 1 |
| Dismiss stale approvals when new commits are pushed | On |
| Require review from Code Owners | On |
| Require approval of the most recent reviewable push | On |
| Require conversation resolution before merging | On |

Bypass: the **Repository admin** role, *For pull requests only*.

- Nothing reaches `main` except through a pull request, for anyone.
- A pull request needs a code owner's (`sre-lead`'s) approval, and a push
  after it needs a new one. The last pusher can't approve: if you pushed
  last to someone else's pull request, merge it with the admin bypass.
- GitHub never lets you approve your own pull request, so you merge yours
  with the admin bypass. *For pull requests only* keeps it there: you still
  can't push to `main`.
- Once approved, **any** user with Write can click merge, the machine user
  included: rulesets don't control who merges. **Merge right after you
  approve.**

**`protected-tags`**, target all tags: *Restrict deletions* and *Block
force pushes* on; bypass the Repository admin role, *Always*. Creating
tags stays open: semantic-release tags each release as
`github-actions[bot]` (`release.yml`).

### Actions

| Where | Setting | Value | Why |
| --- | --- | --- | --- |
| Each repository → Actions → General | Approval for running fork pull request workflows | *Require approval for all external contributors* | A fork's pull request runs nothing without you. |
| Each repository → Actions → General | Workflow permissions | *Read repository contents and packages* | Every workflow declares the permissions it needs. |
| Organization → Actions → Runner groups | `homelab` | stage 8 | The dry-run runner's group. |
| `homelab-proxmox-core` → Environments | `dry-run` | stage 8 | The dry-run's approval gate. |

### Check it

As yourself (an organization owner):

```bash
o=BCochofelHomelab
gh api orgs/$o --jq '{default_repository_permission, members_can_create_repositories, members_can_create_teams, two_factor_requirement_enabled}'
for t in sre-lead sre-team; do
  echo "== $t: $(gh api orgs/$o/teams/$t/members --jq '.[].login' | paste -sd, -)"
  gh api orgs/$o/teams/$t/repos --jq '.[] | "  \(.name): \(.role_name)"'
done
for r in homelab-proxmox-core homelab-proxmox-workloads; do
  echo "== $r"
  gh api repos/$o/$r --jq '{visibility, delete_branch_on_merge}'
  gh api repos/$o/$r/collaborators --jq '.[] | "  \(.login): \(.role_name)"'
  for id in $(gh api repos/$o/$r/rulesets --jq '.[].id'); do
    gh api repos/$o/$r/rulesets/$id | jq -c '{name, enforcement, bypass_actors, rules: [.rules[] | {type, parameters}]}'
  done
  gh api repos/$o/$r/codeowners/errors --jq '.errors'
  gh api repos/$o/$r/actions/permissions/workflow --jq .default_workflow_permissions
done
```

**Expect:** the values in the tables above, `[]` for CODEOWNERS errors,
and `read` for the workflow permissions.

## Stage 3. External accounts and the Proxmox node

1. **Proxmox VE 9** node `pve1` at `192.168.68.20`, with the Ubuntu ISO the
   template boots uploaded to its `local` ISO storage under exactly the
   name `boot_iso_file` expects (`packer/ubuntu-26.04/variables.pkr.hcl`):
   `ubuntu-26.04.1-live-server-amd64.iso`.
2. **Proxmox roles, users and tokens**, and the `ansible` SSH user on the
   node: [`CREDENTIALS.md`](CREDENTIALS.md) step 1.
3. **HCP Terraform:** the organization `homelab-bcochofel-com` (Free), the
   CLI-driven workspace `core-caddy` in **Local** execution mode, and your
   user token: step 2.
4. **Cloudflare:** the `bcochofel.com` zone, and Caddy's DNS-01 token
   (DNS Write and Zone Read on that zone only): step 3.

**Check:** `pveum user token permissions terraform@pve terraform --path /`
on the node lists `TofuApply`'s privileges.

## Stage 4. Keys and secrets

[`CREDENTIALS.md`](CREDENTIALS.md) steps 4 to 7, in order:

1. **The age keys** (step 4): yours and the AI agent's, never at SOPS's
   default path.
2. **`~/.secrets/`** (step 5): `homelab.yaml` and `homelab-ro.yaml` (and
   `ai-agent-git.yaml` in stage 7), with `~/.secrets/.sops.yaml`.
3. **The inventory secrets** (step 5), committed and encrypted:
   `caddy.sops.yaml`, `pihole.sops.yaml`, `all.sops.yaml`. Rebuilding with
   the same age keys, the committed files still open: nothing to redo.
4. **`.claude/settings.json`** (step 6) points at
   `/home/bcochofel/.config/sops/age/ai-agent.txt`.

**Check** (step 7), every line `ok`:

```bash
mise run secrets:check
mise run creds:check
mise run boundary:check
```

## Stage 5. Build: Packer, OpenTofu, Ansible

Always in this order, from your clone, on `main`.

1. **The template** ([`packer/ubuntu-26.04/README.md`](../packer/ubuntu-26.04/README.md)):

   ```bash
   mise run packer:build
   ```

2. **The VMs** ([`TERRAFORM.md`](TERRAFORM.md)): `proxy`, `server01` and
   `runner01`, plus `ansible/inventory/hosts.ini`:

   ```bash
   mise run tofu:init
   mise run tofu:plan      # review it; saves terraform/tfplan
   mise run tofu:apply     # applies exactly that plan
   ```

3. **The configuration** ([`ANSIBLE.md`](ANSIBLE.md)). The Elastic Agent
   play needs homelab-proxmox-workloads' Fleet: its enrollment tokens are
   `fleet_enrollment_tokens` in `all.sops.yaml`. On a rebuild where
   workloads isn't up yet, run the playbooks before it on their own, and
   the whole of `site.yml` once Fleet exists:

   ```bash
   cd ansible
   for p in 00-bootstrap 01-ci-ssh-key 05-dns 10-caddy; do
     ANSIBLE_SOPS_AGE_KEYFILE=~/.config/sops/age/bcochofel.txt ansible-playbook "playbooks/$p.yml" || break
   done
   cd ..
   mise run ansible:site   # everything, once workloads' Fleet is up
   ```

**Check:** `mise run tofu:plan` shows *No changes*, and `ansible:site`
ends with `failed=0` on every host and *All external dependencies are
ready.*

## Stage 6. Network

1. **The QNAP secondaries**, CoreDNS (`.3`) and Pi-hole (`.6`), the ISP
   router's DNS setting and Home Assistant's proxy setting, all set up by
   hand: [`EXTERNAL-DEPENDENCIES.md`](EXTERNAL-DEPENDENCIES.md).
2. **DHCP** hands out the two Pi-holes, `192.168.68.5` and
   `192.168.68.6`, never a CoreDNS address next to them.

**Check:** the DNS tests in the README,
[Test DNS and configure your network](../README.md#test-dns-and-configure-your-network),
and every `caddy_sites` URL presenting a Let's Encrypt certificate.

## Stage 7. The AI agent (optional)

The AI agent works in a devcontainer, as its own GitHub machine user: it
pushes branches and opens pull requests, and never merges, approves, tags
or changes infrastructure. Most of that is enforced by GitHub; the rest by
`.claude/settings.json`.

### The machine user and its token

1. **The account:** `bcochofel-ai-agent`, with its own email address (a
   `+ai-agent` alias of yours works) and two-factor authentication.
2. **The organization:** invite it as a member, and add it to `sre-team`
   only. That's its Write on both repositories; nothing else.
3. **Its token**, signed in as the machine user: a fine-grained personal
   access token, resource owner `BCochofelHomelab`, 90 days, only the two
   repositories:

   | Permission | Access |
   | --- | --- |
   | Contents | Read and write |
   | Pull requests | Read and write |
   | Actions | Read |
   | Issues | Read |
   | Metadata | Read |
   | Everything else (Workflows, Administration, Secrets, Environments, ...) | No access |

   Approve it in *Organization settings → Personal access tokens → Pending
   requests*, then store it as `GH_TOKEN` in `~/.secrets/ai-agent-git.yaml`
   ([`CREDENTIALS.md`](CREDENTIALS.md) step 9). When it expires, a new one
   the same way, then `mise run creds:check`.

### What GitHub enforces, and what it doesn't

| Control | When it acts | What it stops |
| --- | --- | --- |
| The token has **no Workflows permission** | At push | GitHub rejects any push that touches `.github/workflows/`, so an edited workflow never exists on GitHub to run. |
| **CODEOWNERS** + `protected-default` | At merge | Nothing reaches `main` without your review, `mise.toml`, `.claude/settings.json` and `.devcontainer/` included. |

The push-time control matters because a `pull_request` workflow runs the
workflow file from the pull request's branch, not from `main`: CODEOWNERS
alone couldn't stop an edited workflow from running.

What GitHub doesn't stop, and `.claude/settings.json` does (a soft
boundary, so you act accordingly): merging after your approval (merge
right away), creating tags (`git tag` and tag pushes are denied), and
approving (its approval never counts anyway, and `gh pr review` is
denied).

**HTTPS, never SSH.** The machine user pushes with its token over HTTPS
(the devcontainer rewrites SSH remotes): an SSH key can't be limited to
two repositories or set to expire, and the Workflows block applies only
to token pushes.

### MCP servers and the devcontainer

1. **MCP servers** (Proxmox, GitHub, Terraform registry), all read-only:
   [`CREDENTIALS.md`](CREDENTIALS.md) step 8.
2. **The devcontainer**, in the AI agent's own clone
   (`~/Projects/ai-agent/homelab-proxmox-core`), never yours:
   [`DEVCONTAINER.md`](DEVCONTAINER.md) and
   [`CREDENTIALS.md`](CREDENTIALS.md) step 10. In the container, `gh` is
   `.devcontainer/bin/gh`, which runs as `bcochofel-ai-agent` with the
   token from `ai-agent-git.yaml`; never run `gh auth login` there.
3. **`.claude/settings.local.json` in both clones**: `allow` for
   `git push` and `gh pr create` in the agent's (`post-create.sh` writes
   it), `ask` in yours ([`DEVCONTAINER.md`](DEVCONTAINER.md#pushes-and-pull-requests)).

**Check**, in the container: `mise run boundary:check`, every line `ok`,
including its git and GitHub section (commits as `bcochofel-ai-agent`,
`main` requires a code owner, a workflow push is refused). On WSL,
`mise run creds:check` shows the token can push to both repositories but
not administer them.

## Stage 8. The dry-run runner (optional)

### Why it exists

Google's
[*AI engineering for reliable operations*](https://sre.google/resources/practices-and-processes/ai-engineering-reliable-operations/)
asks for a dry-run before every change, and the AI agent can't do one
against live state by design: `ansible-playbook --check` needs the
inventory secrets and root-equivalent SSH, and `tofu plan` needs the HCP
state, which the Free plan can't share read-only. So the dry-runs run on
an **executor**: `runner01`, a self-hosted GitHub Actions runner on the
LAN with its own plan-scoped `ci` identity. You approve each dry-run;
apply stays yours. Reasoning with the agent, execution with CI: the
paper's AI Operator / Actus split.

### How a dry-run runs

1. A pull request changes `terraform/` or `ansible/` (or the dry-run's own
   tooling: `mise.toml`, `mise.lock`, `.sops.yaml`, `ci/`, `dry-run.yml`).
2. `.github/workflows/dry-run.yml` starts, and its jobs on the runner wait
   for the `dry-run` environment.
3. You approve: *Review deployments → dry-run → Approve and deploy*.
   Nothing reaches the runner before that.
4. `runner01` runs `tofu plan` and/or `ansible-playbook --check --diff`,
   as `ci`, one job at a time.
5. A comment on the pull request, *Dry-run of `<sha>`*, shows the plan
   line and the Ansible recap; the full output is an encrypted artifact.
6. The AI agent reads both and, if needed, pushes a fix, which needs a new
   approval.

| Dry-run | Runs on | Credentials |
| --- | --- | --- |
| pre-commit, `tofu validate`, TFLint, Checkov, Trivy, `packer validate`, `ansible-lint`, `--syntax-check` | GitHub-hosted (`ci.yml`), and the AI agent locally | none |
| `tofu plan` | `runner01`, after your approval | `ci@pve!plan` (read-only), an HCP team token, `cipassword` |
| `ansible-playbook --check --diff` | `runner01`, after your approval | the `ci` age key (inventory secrets), the automation SSH key |
| `packer build`, `tofu apply`, `ansible-playbook` | your WSL clone only | yours |

### Setting it up

In this order:

1. **The runner group** (*Organization settings → Actions → Runner groups
   → New runner group*): name `homelab`; *Repository access*: *Selected
   repositories*, both homelab repositories, *Allow public repositories*
   checked; *Workflow access*: **All workflows** (below).
2. **The VM:** `runner01` already exists, from stage 5's `tofu apply`, and
   `site.yml` bootstrapped it.
3. **The runner**, from your clone: a registration token (valid for an
   hour), then the playbook:

   ```bash
   gh api -X POST orgs/BCochofelHomelab/actions/runners/registration-token --jq .token
   mise run ansible:runner   # paste the token at the prompt; later runs: just Enter
   ```

4. **The `ci` identity:** [`CREDENTIALS.md`](CREDENTIALS.md) step 11 (the
   `ci` age key, the automation SSH key, `ci@pve!plan`, the HCP team
   token, the `ci/` files, the inventory files re-encrypted to `ci`), then
   `mise run ansible:site` to authorize the automation key on every host.
   Rebuilding with the same `ci` key and committed files, only the
   tokens are new.
5. **The `dry-run` environment** (*`homelab-proxmox-core` → Settings →
   Environments → New environment*): name `dry-run`; *Required reviewers*
   `sre-lead`; *Prevent self-review* off (you approve dry-runs of your own
   pull requests); *Allow administrators to bypass* **off**; *Deployment
   branches*: no restriction (a `pull_request` job runs from the pull
   request's merge ref, which no branch rule matches); environment secret
   `CI_AGE_KEY`, the `AGE-SECRET-KEY-...` line of
   `~/.config/sops/age/ci.txt`. Click **Save protection rules**: it's a
   separate button.
6. **Check:**

   ```bash
   mise run runner:check   # every line ok, the last two: reviewer sre-lead, no admin bypass
   mise run tofu:plan-ci   # No changes
   mise run ansible:check  # failed=0; only CoreDNS's zone serial and restart change
   ```

7. **A test pull request** touching `ansible/`: the dry-run waits for you,
   then posts its comment. A fork's pull request must skip *What changed*
   and reach nothing.

To register the runner again (after removing it from GitHub, or the red
button), delete its registration first, then repeat step 3:

```bash
ssh ubuntu@runner01.homelab.bcochofel.com \
  'sudo rm -f /opt/actions-runner/.runner /opt/actions-runner/.credentials /opt/actions-runner/.credentials_rsaparams'
```

### The `ci` identity

| Piece | What | Limit |
| --- | --- | --- |
| Proxmox | `ci@pve!plan`, role `AiAgentRO` | Read-only: Proxmox refuses a write. |
| HCP Terraform | an `owners` team token | Can write state (the Free plan has no read-only token): an accepted risk, limited to this organization, used only in a job you approved that only plans. |
| SSH | the automation key, next to yours on every VM and the Proxmox `ansible` user | Root-equivalent, like yours: used only by `ansible:check`, never in the devcontainer. |
| SOPS | the `ci` age key: `ci/`, the inventory files | Never a recipient of `~/.secrets/`. |
| GitHub | `CI_AGE_KEY`, a `dry-run` environment secret | The only secret GitHub holds; the job hands it to SOPS as `SOPS_AGE_KEY`, never written to disk. |

### The runner VM

- **`runner01`**, `192.168.68.9`, 2 vCPU, 4 GB, 50 GB (the template's
  disk, the smallest a clone can have), group `github_runner`, a
  `dns_hosts` entry, no Caddy site. **Outbound only**: GitHub, package
  registries, HCP, the Proxmox API, SSH to LAN hosts.
- **Unprivileged:** the runner runs as `gha-runner` (no login shell, no
  sudo, not in `docker`), as a systemd service. Docker is stopped and
  masked; no job needs it.
- **Persistent, cleaned per job:** the runner empties each job's temp
  directory, and a root-owned job-completed hook empties its workspace.
  Every job gets `HOMELAB_DRY_RUN=1`, for `site.yml`'s guard.
- **Self-update on:** the `github_runner` role installs a pinned,
  checksum-verified version once; the runner updates itself after that,
  since GitHub stops sending jobs to runners it considers too old.
- **Telemetry:** its Elastic Agent is in `homelab-core` like every VM; its
  own Fleet policy (no Docker integration, the runner's `_diag` logs) is
  homelab-proxmox-workloads' to define.

### Why *All workflows*

A runner group limited to selected workflows pins each one to a branch,
such as `dry-run.yml@refs/heads/main`, but a `pull_request` job runs from
the pull request's merge ref (`refs/pull/<n>/merge`): it would never
match, and every dry-run would wait forever. So the group can't refuse a
workflow edited in a pull request. What does: the machine user's token
can't push `.github/workflows/`, only you commit workflow files, and every
job waits for your approval.

### The workflow

`dry-run.yml`, four jobs:

- **`changes`** (GitHub-hosted, no secrets) lists the pull request's
  files and decides which of the next two run.
- **`plan`** and **`check`** run on `[self-hosted, homelab]` with
  `environment: dry-run`, `contents: read`, the toolchain installed per
  job by `jdx/mise-action` exactly as `mise.lock` pins it.
- **`report`** (GitHub-hosted, no checkout) posts or updates the pull
  request's comment, with the workflow's only write permission
  (`pull-requests: write`): none of the pull request's code runs where
  that token is.

And around them:

- `pull_request` only, never `pull_request_target`; same-repository pull
  requests only, so a fork's never reaches the runner.
- `permissions: {}` by default. One concurrency group per pull request,
  `cancel-in-progress`: a new push cancels that pull request's previous
  dry-run, even one still waiting for approval. `runner01` is a single
  runner, so jobs never overlap anyway, and `tofu:plan-ci` waits up to
  five minutes for the state lock; a second runner would need a shared
  job-level group.
- Every action, in every workflow, pinned to a commit SHA with its version
  in a comment, and no checkout keeps git credentials; `actionlint`
  (`.github/actionlint.yaml` declares the `homelab` label) and `zizmor`
  run in pre-commit and CI.
- **Only you commit workflow files.** The AI agent writes and lints them in
  its clone and puts them in its pull request's description; you add them
  to its branch, from your clone or GitHub's web editor. Its CI is red
  until you do.

### Output: the logs are public

Both repositories are public, so are Actions logs, and a full plan or
`--diff` shows hostnames, IPs and the DNS zone.

- The log, the run summary and the pull request comment get only `Plan: X
  to add, Y to change, Z to destroy` and the Ansible recap.
- The full output is encrypted with `age` to your key and the `ai-agent`
  key (both public keys in `dry-run.yml`), an artifact (`plan` or `check`)
  kept 7 days. `sensitive` values and `no_log` tasks are already masked.
  To read it, from a run whose job has finished:

  ```bash
  gh run list --workflow dry-run.yml --branch <branch>   # the run's ID
  gh run download <run-id> -n plan -D /tmp/dry-run       # or -n check
  age -d -i ~/.config/sops/age/bcochofel.txt /tmp/dry-run/plan.txt.age | less
  rm -rf /tmp/dry-run
  ```

- `tfplan` is never uploaded: plan files hold sensitive values in clear
  text.

Making the repositories private isn't an option on the Free plan:
rulesets and environment reviewers protect only public repositories
there.

### The dry-run tasks

Shared by CI and you, so a dry-run can be repeated from your clone, and
all denied to the AI agent:

- **`tofu:plan-ci`:** `tofu plan -refresh=false` with `ci/dry-run.sops.yaml`;
  never writes `tfplan`. No refresh, because refreshing a VM reads its
  disks' volume info, which Proxmox allows only with `VM.Config.Disk`, a
  write privilege `ci@pve!plan` deliberately lacks
  ([bpg/terraform-provider-proxmox#3141](https://github.com/bpg/terraform-provider-proxmox/issues/3141)).
  It shows what the code changes against the state, not changes made by
  hand since the last apply; your `tofu:plan` still refreshes.
- **`ansible:check`:** decrypts the automation key into a temporary
  directory, writes `inventory/hosts.ini` from the state's
  `ansible_inventory` output, and runs `site.yml --check --diff --limit
  '!github_runner'`. The runner never dry-runs itself.
- **`ansible:runner`:** `30-github-runner.yml`, with your key.
- **`runner:check`:** over SSH as you: `gha-runner` has no sudo and no
  Docker, no age key outside a job's temp directory, the runner is
  registered and runs as `gha-runner`, `HOMELAB_DRY_RUN=1`, the hook is
  root's. Then, from your machine: `ci@pve!plan` gets a 403 on a write, and
  the `dry-run` environment has a required reviewer and no administrator
  bypass. Without that reviewer, a pull request's code runs on `runner01`
  with the `ci` key, unapproved: the environment is the boundary.

`tofu:plan-ci` and `ansible:check` take the `ci` key from `SOPS_AGE_KEY`
(CI) or `~/.config/sops/age/ci.txt` (your machine).

### Check mode in the playbooks

- Read-only `command`/`shell`/`uri`/`wait_for` tasks run in check mode too:
  `check_mode: false # read-only: <why>`, on the same line, or the
  pre-commit hook `check_mode_false_read_only` fails. Anything that changes
  a host stays skipped.
- `site.yml`'s first play refuses anything but `--check` where
  `HOMELAB_DRY_RUN=1`: a backstop, since a pull request could remove it.
- Every dry-run shows the CoreDNS zone file's new serial and a restart: the
  serial is the time of the run, by design (`db.zone.j2`).

## Red button

One procedure, yours only, to stop everything the AI agent and the
runner can do. Each step cuts a path on its own, so a partial run still
helps.

### Level 1: pause (something looks wrong; reversible)

1. **The agent's write access:** *Organization → Teams → `sre-team` →
   Members* → remove `bcochofel-ai-agent`. Its Write ends at once, even
   with a valid token.
2. **The agent's session:** close the devcontainer window, or `docker stop
   <container>` from WSL.
3. **The runner:** *Organization settings → Actions → Runners* →
   `runner01` → *Remove*, and `sudo systemctl stop 'actions.runner.*'` on
   the VM.
4. **The workflow:** *Actions → Dry-run → ⋯ → Disable workflow*, in both
   repositories.

**Restore** in reverse: enable the workflow, re-register the runner
([Setting it up](#setting-it-up), step 3), add the machine user back to
`sre-team`, reopen the devcontainer; then `mise run runner:check`, and
`mise run boundary:check` in the container.

### Level 2: revoke (a credential may have leaked)

Level 1 first, then:

| Identity | Revoke | Then rotate |
| --- | --- | --- |
| The machine user's token | *Organization settings → Personal access tokens → Active tokens* → revoke | A new token in `ai-agent-git.yaml` ([stage 7](#the-machine-user-and-its-token)) |
| The `ai-agent` age key | Remove it from `~/.secrets/.sops.yaml` and `dry-run.yml`; `updatekeys` `homelab-ro.yaml` and `ai-agent-git.yaml` | Everything in those two files: the `ai-agent@pve` token, the read-only GitHub token, the machine user's token |
| The `ci` age key | Delete `CI_AGE_KEY`; remove the `ci` recipient from `.sops.yaml` and `updatekeys` its files | Everything it could open: the Cloudflare token, the Pi-hole password, the Fleet tokens, `ci@pve!plan`, the HCP team token, `cipassword`, the automation SSH key (and its public half on every host) |
| `runner01` | Treat it as compromised: destroy it and rebuild it from the template | The `ci` row |

Afterwards: `mise run secrets:check`, `creds:check`, `boundary:check` and
`runner:check`.

### Drill

Level 1 every quarter: a push from the devcontainer fails with 403, a new
pull request's dry-run never starts, and `gh pr checks` still works
(read-only). Record each drill here.

| Date | Result |
| --- | --- |
| — | Not run yet |

## Final verification

The same place as before, when all of these hold:

```bash
mise run doctor           # no problems
mise run secrets:check    # every line ok
mise run creds:check      # every line ok
mise run boundary:check   # every line ok (and in the devcontainer, stage 7)
mise run tofu:plan        # No changes
mise run ansible:site     # failed=0 everywhere; all external dependencies ready
mise run runner:check     # every line ok (stage 8)
mise run tofu:plan-ci     # No changes (stage 8)
mise run ansible:check    # failed=0 (stage 8)
```

And, on GitHub: [stage 2's checks](#check-it) match its tables, and a
test pull request touching `ansible/` gets its dry-run comment after your
approval.
