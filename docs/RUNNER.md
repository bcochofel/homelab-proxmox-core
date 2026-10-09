# Dry-run runner

The design of the self-hosted GitHub Actions runner that dry-runs pull
requests against the live homelab: `tofu plan` and
`ansible-playbook --check --diff`. It's being built in steps
([Build order](#build-order)); until those are done, this page is the
design they follow. Apply stays yours: nothing here adds a way for CI or
the AI agent to change infrastructure.

## Why

Google's
[*AI engineering for reliable operations*](https://sre.google/resources/practices-and-processes/ai-engineering-reliable-operations/)
asks for a mandatory dry-run before any change. The AI agent can't do one
against live state, by design:

- `ansible-playbook --check` needs the inventory secrets
  (`group_vars/*.sops.yaml`, your key only) and root-equivalent SSH on
  every host;
- `tofu plan` needs the HCP Terraform state, and the Free plan can't issue
  a read-only token ([`CREDENTIALS.md`](CREDENTIALS.md) step 2).

Giving either to the agent would break its read-only boundary. So the
dry-runs move to an **executor**: a runner on the LAN that holds its own
`ci` identity. The agent opens a pull request as its machine user
([`GITHUB.md`](GITHUB.md)), you approve the dry-run, the runner runs it,
and the agent reads the result with `gh`. Reasoning stays with the agent
and execution with CI, the paper's AI Operator / Actus split.

## How a dry-run runs

1. A pull request changes `terraform/` or `ansible/`.
2. `dry-run.yml` starts and waits on the `dry-run` environment.
3. You approve it (*Review deployments → Approve*). Nothing reaches the
   runner before that.
4. The runner, `runner01`, decrypts the `ci` credentials into the job's
   temporary directory and runs `tofu plan` and/or
   `ansible-playbook --check --diff`.
5. The run page shows a summary; the full output is an encrypted
   artifact ([Output](#output-the-logs-are-public)).
6. The AI agent reads both and, if needed, pushes a fix, which needs a
   new approval.

| Dry-run | Runs on | Credentials |
| --- | --- | --- |
| pre-commit, `tofu validate`, tflint, Checkov, Trivy, `packer validate`, `ansible-lint`, `--syntax-check` | GitHub-hosted (`ci.yml`), and the AI agent locally | none |
| `tofu plan` | `runner01`, after your approval | `ci@pve!plan` (Proxmox, read-only), an HCP token, `cipassword` |
| `ansible-playbook --check --diff` | `runner01`, after your approval | the `ci` age key (inventory secrets), the automation SSH key |
| `packer build`, `tofu apply`, `ansible-playbook` | your WSL clone only | yours |

## The `ci` identity

One identity, scoped to planning. How to create each piece:
[`CREDENTIALS.md`](CREDENTIALS.md) step 11.

- **Proxmox:** user `ci@pve`, token `ci@pve!plan`, with the existing
  read-only `AiAgentRO` role. A plan only reads the API, so Proxmox itself
  refuses a write.
- **HCP Terraform:** a token that **can write state**. The Free plan has
  no read-only token, so this is an accepted risk, limited by the
  environment approval and by `plan` never running `apply`. Reading the
  state without writing it stays an open item (`TODO-SRE-AI.md` A1).
- **SSH:** an automation keypair, its public half next to yours on every
  VM and on the Proxmox nodes' `ansible` user: the Packer template for new
  VMs, the `ci_ssh_key` role (`playbooks/01-ci-ssh-key.yml`) for the rest.
  It's never in the devcontainer.
- **SOPS:** a `ci` age key, a recipient of:
  - `ansible/inventory/group_vars/*.sops.yaml` (you + `ci`);
  - `ci/dry-run.sops.yaml`, committed (you + `ci`): `TF_VAR_proxmox_api_token`
    (`ci@pve!plan=...`), `TF_VAR_cipassword`, `TF_TOKEN_app_terraform_io`;
  - `ci/ssh_ed25519.key.sops`, committed (you + `ci`): the automation
    private key.

  Never of `~/.secrets/*`: the runner never holds your credentials. The
  `ai-agent` key is a recipient of none of these files.
- **GitHub stores one secret:** `CI_AGE_KEY`, on the `dry-run`
  environment only, never a repository or organization secret. The job
  hands it to SOPS as `SOPS_AGE_KEY`, so the key itself never touches the
  disk. Everything else reaches the job through `sops exec-env`, as in the
  `mise run` tasks, and nothing is written outside `$RUNNER_TEMP`, which
  is removed after each job.
- **HCP Terraform token:** an `owners` team token, limited to
  `homelab-bcochofel-com` and revocable without touching yours.

## The runner VM

- **`runner01`**, `192.168.68.9`, cloned from the `ubuntu-26.04` template
  by `terraform/` like `proxy` and `server01`, in the generated
  `hosts.ini` as group `github_runner`, with a `dns_hosts` entry. 2 vCPU,
  4 GB RAM, 50 GB disk (the template's, the smallest a clone can have):
  it shares the one Proxmox node with everything else.
- **Outbound only:** GitHub, package registries, HCP, the Proxmox API and
  SSH to LAN hosts. No inbound port, no Caddy site, no port forward.
- **Unprivileged:** the runner runs as `gha-runner`, a system user with
  no login shell, no sudo and **not** in the `docker` group
  (root-equivalent), as a systemd service. The template's Docker
  (`docker.service` and `docker.socket`) is stopped and masked on this VM;
  no job needs it.
- **Persistent, cleaned per job.** The runner empties each job's temp
  directory itself; a job-completed hook, owned by root, empties its
  workspace. Ephemeral (JIT) runners are a later step.
- **Every job gets `HOMELAB_DRY_RUN=1`** (the runner's `.env`), for
  `site.yml`'s guard ([Check mode](#check-mode-in-cores-playbooks)).
- **Self-update on.** The role installs a pinned, checksum-verified
  version once; after that the runner updates itself, since GitHub stops
  sending jobs to runners it considers too old. The pin is only the
  starting version, and the role never reinstalls over a newer one.
- **Registration:** the `github_runner` role in
  `ansible/playbooks/30-github-runner.yml`, not part of `site.yml`, run by
  you ([Registering the runner](#registering-the-runner)). It registers
  only when `.runner` is absent, with the short-lived registration token
  from a private prompt, and `no_log` on every task that touches it.
- **Telemetry:** its Elastic Agent is enrolled like every host's
  (`site.yml`). Its own Fleet policy (no Docker integration, the runner's
  `_diag` logs for the audit trail) is homelab-proxmox-workloads' to
  define; until then it's in `homelab-core`, whose Docker integration has
  nothing to read there.

### Which repositories can use it

The runner is registered once, to the **organization runner group
`homelab`**, with the label `homelab`:

- **Repository access:** *Selected repositories*, `homelab-proxmox-core`
  and `homelab-proxmox-workloads`, with *Allow public repositories*
  checked (a group serves only private repositories by default).
- **Workflow access:** *All workflows*. A group limited to selected
  workflows pins each one to a branch, such as
  `.../dry-run.yml@refs/heads/main`, but a `pull_request` job runs from
  the pull request's merge ref (`refs/pull/<n>/merge`): it would never
  match, and every dry-run would wait for a runner forever. So the group
  can't refuse a workflow edited in a pull request. What does: the
  machine user's token can't push `.github/workflows/`, only you commit
  workflow files, and every job waits for your `dry-run` approval.
  Whether a ref pattern for merge refs works (which would at least keep
  other workflow files off the runner) is tried with `dry-run.yml`
  (step 6).

### Registering the runner

1. A registration token, valid for an hour: *Organization settings →
   Actions → Runners → New runner → New self-hosted runner*, and copy the
   value after `--token` in the *Configure* commands (ignore the rest of
   that page; the playbook does it). Or, with your own `gh` login on WSL:

   ```bash
   gh api -X POST orgs/BCochofelHomelab/actions/runners/registration-token --jq .token
   ```

2. From your clone: `mise run ansible:runner` and paste the token at its
   prompt. Later runs need no token: press Enter.
3. `mise run runner:check`: every line `ok`. The runner shows as *Idle* in
   the `homelab` group.

To register it again (after removing it from GitHub, or a red-button
pause), delete its registration on the VM first, then repeat the steps:

```bash
ssh ubuntu@runner01.homelab.bcochofel.com \
  'sudo rm -f /opt/actions-runner/.runner /opt/actions-runner/.credentials /opt/actions-runner/.credentials_rsaparams'
```

## The workflow

`.github/workflows/dry-run.yml`:

- **`pull_request` only, never `pull_request_target`**, and every job
  requires `github.event.pull_request.head.repo.full_name ==
  github.repository`: a fork's pull request never reaches the runner.
  "Require approval for all external contributors" is on as well.
- **`environment: dry-run`, with you as required reviewer.** This is the
  actual boundary: a pull request can change the playbooks and the
  workflow itself, so nothing inside the repo can be. *Prevent
  self-review* stays off, so you can approve dry-runs of your own pull
  requests.
- **`permissions: contents: read`**, nothing else.
- **One concurrency group** (`dry-run`, `cancel-in-progress: false`), so
  plans and checks never overlap on the state lock or the hosts.
- **`paths` filters:** `plan` when `terraform/**` changed, `check` when
  `ansible/**` changed.
- **Every action pinned to a commit SHA**, in every workflow; `actionlint`
  and `zizmor` in `mise.toml` and pre-commit.
- **Only you commit workflow files.** The machine user's token can't push
  them; the AI agent puts them in the pull request description and you
  add them from your clone.

Every new push dismisses earlier approvals and needs a new dry-run
approval.

## Output: the logs are public

Both repositories are public, so Actions logs are too, and a full plan
or `--diff` shows internal hostnames, IPs and the DNS zone.

- The log and the run summary (`$GITHUB_STEP_SUMMARY`) get only
  `Plan: X to add, Y to change, Z to destroy` and the Ansible recap.
- The full output is encrypted with `age` to your key and the `ai-agent`
  key and uploaded as a short-retention artifact. The AI agent downloads
  it with its token (Actions: read) and decrypts it with its own key. It
  holds no secrets: `sensitive` values and `no_log` tasks are already
  masked.
- `tfplan` is never uploaded: plan files hold sensitive values in clear
  text.

Making the repositories private isn't an option on the Free plan:
rulesets and environment reviewers protect only public repositories
there.

## mise tasks

Shared by CI and you, so a dry-run can be repeated from your clone with
the `ci` key. Both are denied to the AI agent, which can't open their
files anyway.

- **`tofu:plan-ci`:** `tofu init` and `tofu plan` inside
  `sops exec-env ci/dry-run.sops.yaml`, with the `ci` key. Never writes
  `tfplan`.
- **`ansible:check`:** decrypts the automation key into a directory under
  `$RUNNER_TEMP` (or the system temp directory outside CI), removed when it
  ends; writes `inventory/hosts.ini` from the `ansible_inventory` output in
  the state, with the plan credentials (the same file `tofu apply` writes;
  it's gitignored, so a checkout has none); then runs
  `ansible-playbook playbooks/site.yml --check --diff --limit '!github_runner'`
  with the `ci` key. The runner never dry-runs or manages itself.
- **`ansible:runner`:** `30-github-runner.yml`, with your key (the
  playbook loads the inventory's secrets like any other).
- **`runner:check`:** from your clone, over SSH as you, prints
  `ok`/`FAIL`, never a value: `gha-runner` can't `sudo -n true`, isn't in
  `docker`, Docker is masked and stopped with no socket, no age key exists
  outside a job's temp directory, the runner is registered and its
  service runs as `gha-runner`, jobs get `HOMELAB_DRY_RUN=1`, and the
  job-completed hook is root's. From step 4, also: `ci@pve!plan` gets a
  403 on a harmless write.

`tofu:plan-ci` and `ansible:check` take the `ci` key from `SOPS_AGE_KEY`
when it's set (CI), and from `~/.config/sops/age/ci.txt` otherwise (your
machine). All four tasks are denied to the AI agent: they use the `ci`
key, your key or your SSH access.

`boundary:check` gains two checks: the `ai-agent` key is refused by both
`ci/` files, and no `ci` key exists in the devcontainer.

## Check mode in core's playbooks

`--check` must pass against the live hosts before the `check` job is
useful:

- **Read-only `command`/`shell`/`uri` tasks** get `check_mode: false` and
  `changed_when: false`; anything that changes a host stays skipped.
  Conditions on a skipped result use `default(...)` or
  `not ansible_check_mode`.
- **A pre-commit check lists every `check_mode: false`**, so each one is
  reviewed.
- **`site.yml` refuses a real run when `HOMELAB_DRY_RUN=1`**, which the
  runner's service sets. A backstop only: a pull request can remove it.
- Tasks that handle secrets keep `no_log: true`, which also hides their
  `--diff`.

## Red button: the runner's half

The AI agent's half is in [`GITHUB.md`](GITHUB.md#red-button-stopping-the-ai-agent).
Together they're one procedure, all yours.

**Level 1, pause** (add these to the agent's two steps; each cuts a path
on its own):

- **The runner:** *Organization (or repository) settings → Actions →
  Runners* → `runner01` → *Remove*, and on the VM
  `sudo systemctl stop 'actions.runner.*'`.
- **The workflow:** *Actions → Dry-run → ⋯ → Disable workflow*, in both
  repositories.

**Restore** in reverse: enable the workflow, start and re-register the
runner ([Registering the runner](#registering-the-runner), with a new
token), then run `mise run runner:check`.

**Level 2, revoke:**

| Identity | Revoke | Then rotate |
| --- | --- | --- |
| The `ci` age key | Delete the `CI_AGE_KEY` environment secret; remove the `ci` recipient from `.sops.yaml` and `updatekeys` the files it opened | Everything it could decrypt: the Cloudflare token, the Pi-hole password, `ci@pve!plan`, the HCP token, `cipassword`, the automation SSH key (remove its public half from every host) |
| `runner01` | Treat it as compromised: destroy it and rebuild it from the template | The `ci` row above |

Afterwards, run `mise run secrets:check`, `creds:check`, `boundary:check`,
and `runner:check` on the rebuilt runner.

**Drill:** Level 1 once the dry-run workflow works, then every quarter. A
push from the devcontainer fails with 403, a new pull request's dry-run
never starts, and `gh pr checks` still works (read-only). Record each
drill below.

| Date | Result |
| --- | --- |
| — | Not run yet |

## Build order

One pull request each; 🧑 marks what only you can do.

1. **This design.**
2. **`runner01`** in `terraform/`, its inventory group and DNS entry.
   🧑 `mise run tofu:plan`, `tofu:apply`.
3. **The `github_runner` role and playbook**, `ansible:runner` and
   `runner:check`. 🧑 The `homelab` runner group, the playbook with a
   registration token, `runner:check`.
4. **The `ci` identity:** the `.sops.yaml` rules, the automation SSH key's
   public half (the Packer template and the `ci_ssh_key` role), the
   `ansible_inventory` output, the two mise tasks, the deny rules and the
   checks. 🧑 Everything in [`CREDENTIALS.md`](CREDENTIALS.md) step 11:
   the `ci` key, the automation keypair, the Proxmox and HCP tokens, the
   `ci/` files, `updatekeys` on the inventory files, the `dry-run`
   environment with `CI_AGE_KEY`.
5. **Check-mode fixes** and the `HOMELAB_DRY_RUN` guard. 🧑 Run
   `mise run ansible:check` and share the recap.
6. **`dry-run.yml`**, the SHA pins, `actionlint` and `zizmor`. 🧑 Commit
   the workflow files from your clone; a test pull request and a fork pull
   request.

Done when a pull request touching `terraform/` and `ansible/` gets a plan
and a check recap after your approval, a fork's pull request never
reaches the runner, and `boundary:check` and `runner:check` pass.

## Open questions

To settle before the step that needs them:

- **Whether `plan` opens SSH to the node (step 4).** The provider is
  configured with SSH (`terraform/providers.tf`), but `modules/vm` uses
  nothing that needs it. The first `ci` plan proves it; if it asks for
  SSH, nothing is widened to make it work.
- **A ref pattern for the runner group's workflow access (step 6):** see
  [Which repositories can use it](#which-repositories-can-use-it).
