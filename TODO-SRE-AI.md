# TODO — SRE AI-autonomy

Homelab-wide roadmap for applying Google's
[*AI engineering for reliable operations*](https://sre.google/resources/practices-and-processes/ai-engineering-reliable-operations/)
to this homelab. It covers both repos:

- **`homelab-proxmox-core`** (this repo): Caddy, CoreDNS, Pihole.
- **`homelab-proxmox-workloads`**: every workload behind the edge, using
  OpenTofu and Terramate.

Both repos are built from scratch with this model in place from the first
deploy. Credentials and identities come first (Phase A), so every later
step runs on the right principal from day one.

**Scope: runtime health.** Provisioning (`packer build`, `tofu apply`,
`ansible-playbook` against live hosts) stays human-gated: `ask` on build,
apply and playbook runs, `deny` on `destroy`. Nothing in this file widens
that.

**Ticked items** are implemented and verified. They stay in the file as
a record. Credential and boundary items are verified by
`docs/CREDENTIALS.md` step 7 (`mise run secrets:check`, `creds:check`,
`boundary:check`), devcontainer items by `docs/DEVCONTAINER.md`
("Prove the boundary"). Re-run those checks to confirm a ticked item
still holds.

## The autonomy ladder

| Level | Detect | Investigate | Mitigate | Homelab meaning |
| --- | --- | --- | --- | --- |
| L0 Manual | human | human | human | A human notices a problem and asks the AI agent. |
| L1 Assisted | auto | auto | human | Kibana alerts fire; an agent investigates read-only and files a GitHub issue with evidence and a recommended fix. |
| L2 Partial | auto | auto | auto, **after human approval** | The recommended fix is a catalogued action; the human approves it on the issue and an executor runs it. |
| L3 High | auto | auto | auto, bounded | A short list of pre-approved, self-verifying actions runs without approval. Anything else drops back to L2. |
| L4 Full | auto | auto | auto, open-ended | **Out of scope.** |

Each level is unlocked by evidence, not by a date:

- **L0 → L1:** detection and read-only investigation tooling exists
  (Phases A–C).
- **L1 → L2:** investigations reliably pick the right action (measured in
  Phase D), and a safe actuation path exists (Phase E).
- **L2 → L3:** a sustained approval record for that specific action type,
  with no rejected or reverted runs, and the guardrails below tested.

## Principles (the paper's safety trifecta and guardrails)

These rules apply to every item below.

- **Transparency.** Every agent run leaves a reviewable trace: signals
  queried, hypotheses considered, evidence, confidence and proposed
  action. Traces land in a GitHub issue and in the audit trail (A2).
- **Real-time risk evaluation.** Before any action, check the context: a
  deploy or `tofu apply` in progress, another open incident on the same
  component, remaining error budget. When risk is elevated, downgrade to
  L2 (ask a human).
- **Progressive authorization.** Autonomy is granted per action type,
  never as a blanket write grant, and is earned through Phase D evidence.
- **No ambient access, least privilege.** Agent identities are separate
  from the human's (A3). Read-only must hold at the credential/RBAC
  level, proven by a negative test.
- **Circuit breakers.** Rate-limit agent actions, stop after repeated
  failures on the same target, keep everything interruptible.
- **Mandatory dry-run.** Every catalogued action has a dry-run mode
  (`tofu plan`, `kubectl --dry-run=server`, `docker compose config`,
  `ansible --check`), and the executor runs it first.
- **Safe-by-default actuation.** Agents never get raw tools. They call a
  narrow executor whose actions can't take down core DNS or the proxy on
  their own. Reasoning (the investigation agent) stays separate from
  execution (the executor), as in the paper's AI Operator / Actus split.
- **Red button.** One documented, tested way to stop all agent actions at
  once: revoke the executor's token and disable the scheduled trigger.

## Phase A — Foundations: credentials and telemetry, before anything else

### A1. Identity: one principal per role

One identity per **role**, shared across tools. `tofu plan`,
`packer validate` and read-only investigation all need the same Proxmox
read access, so one RO token covers them. AI agent write actions only
run after the human approves an `ask` prompt, under the human's RW
credential; the audit trail (`labels.source`, A2) attributes who ran what.

| Principal | Proxmox | HCP | MCP | Allowed |
| --- | --- | --- | --- | --- |
| `ai-agent` | `ai-agent@pve!ai-agent` **RO** | none until a RO state credential exists (below) | investigation MCPs (RO) | fmt/lint/validate; RO investigation; **plan** once it has RO state access |
| `terraform` | `terraform@pve!terraform` **RW** | RW | none | everything incl. **apply** |
| `packer` | `packer@pve!packer` | none | none | template builds |
| `ci` | `ci@pve!plan` **RO** (`AiAgentRO`) | RW (Free plan has no RO token; accepted risk, A10) | none | `tofu plan` and `ansible-playbook --check`, on the self-hosted runner only, after the `dry-run` environment approval |
| `ci` apply (later) | `ci@pve!apply` (`TofuApply`) | RW | none | apply, in CI only, behind its own `apply` environment |
| `ai-agent` on GitHub | none | none | none | push its own branches, open PRs, read checks and run logs, as a machine user; never `.github/workflows/**`, merge, approve or tag |
| `ai-agent-scheduled` (later) | RO | RO | investigation MCPs (RO) | unattended investigation only |
| `ai-executor` (Phase E) | per-action, minimal | none | none | runs catalogued, approved actions only |

`plan` is a read-only API operation, so one RO token covers the whole
dry-run loop, and `apply` is rejected by the API itself — once the agent
can read state without being able to write it.

- [x] Create the Proxmox roles (`PackerBuild`, `TofuApply`, `AiAgentRO`),
      users and `--privsep 1` tokens (`packer@pve!packer`,
      `terraform@pve!terraform`, `ai-agent@pve!ai-agent`) following
      `docs/CREDENTIALS.md`, then run its "Verify the boundary" checks.
      If `tofu plan` fails a permission check as `ai-agent`, add the
      specific *read* privilege the error names, never a write one (and
      guest-agent access limited to `VM.GuestAgent.Audit`).
- [x] HCP Terraform: an RW token for `terraform`, per workspace.
- [ ] Read-only state access for `ai-agent`, so it can run the dry-run
      (`tofu plan -lock=false`). The HCP Terraform Free plan has no team
      management, so it can't issue a read-only token; until this is
      done the agent never plans against real state. Options: HCP
      Essentials (a `Read` team token), or a backend with read-only
      credentials (e.g. S3-compatible storage with a read-only key).
      Then restore a `tofu:plan-ro` task using `~/.secrets/homelab-ro.yaml`.
- [x] A dedicated `ai-agent` age identity, used only for decrypting the
      RO secrets file (A4).
- [ ] Ansible identity is SSH keys: one automation keypair, its public half
      added to both repos' Packer templates next to the human's key,
      reserved for the CI runner. It is **not** given to the `ai-agent`
      devcontainer (see A7). Core first: its Packer template, the
      `common` role (existing VMs) and the Proxmox nodes' `ansible` user;
      the private half committed encrypted as `ci/ssh_ed25519.sops`.
- [ ] `ci` principal for dry-runs: Proxmox `ci@pve!plan` (`AiAgentRO`),
      a `ci` age key, and `ci/dry-run.sops.yaml` (`TF_VAR_proxmox_api_token`,
      `TF_VAR_cipassword`, `TF_TOKEN_app_terraform_io`), encrypted to the
      human + `ci` keys only. The `ci` key is also a recipient of
      `ansible/inventory/group_vars/*.sops.yaml`, never of `~/.secrets/*`.
      GitHub holds one secret, `CI_AGE_KEY`, on the `dry-run` environment.
- [ ] Self-hosted GitHub Actions runner holding the `ci` principal (A10).
      Dry-run only; a CI apply path comes later, separately.
- [ ] The agent's own GitHub identity: a machine user in the
      `BCochofelHomelab` org, Write on the two homelab repos through the
      `sre-team` team, with a 90-day fine-grained PAT (Contents and Pull
      requests read/write; Actions, Metadata and Issues read; **no**
      Workflows, Administration, Secrets or Environments) in
      `~/.secrets/ai-agent-git.yaml` (human + `ai-agent` keys). git and
      `gh` get it from a credential helper and a wrapper in the
      devcontainer only. Each repo's `protected-default` /
      `protected-tags` rulesets apply to it unchanged (bypass: repo admin
      only); every file is owned by `sre-lead`, which it's never in, so
      its approvals never count (`docs/GITHUB.md`).
- [ ] `ai-agent-scheduled` (RO) for unattended, alert-triggered
      investigation, with its own `labels.source: "ai-agent-scheduled"`.
      Likely a headless container or CronJob on the workloads K3s cluster.

### A2. Command audit trail

Log every command from both the human and the agent, so trajectories can
be told apart and replayed (Phase D). Use an ECS-native schema from the
start.

- [ ] zsh hook (`~/.zshrc` or a sourced file): `preexec`/`precmd` via
      `add-zsh-hook` (additive, so p10k's hooks are untouched), appending
      one NDJSON line per command to `~/.command_audit.jsonl` with these
      fields: `@timestamp`, `user.name`, `host.name`,
      `process.working_directory`, `process.command_line`,
      `process.exit_code` (`$?`, captured first in `precmd`),
      `event.duration` (ns; `zmodload zsh/datetime` for
      `$EPOCHREALTIME`), `event.kind: "event"`,
      `event.category: ["process"]`, `labels.source: "zsh"`. Build lines
      with `jq -n --arg`/`--argjson` so quoting in commands can't break
      them.
- [ ] AI agent `PostToolUse` hook (matcher `"Bash"`) in Claude Code's user-level
      `~/.claude/settings.json`, writing to the same file with
      `labels.source: "claude-code"` and `labels.session_id`. The Bash
      `tool_response` has no structured exit code, so `process.exit_code`
      is absent for these entries (accepted, Bronze tier).
- [ ] Ship the file to Elastic (custom-logs input,
      `json.keys_under_root: true`). No transformation needed.
- [ ] Ship the MCP servers' logs too: `terraform-mcp-server` already
      writes JSON lines to `~/.local/state/mcp/terraform-mcp-server.log`
      (`.mcp.json`); add the same for the Proxmox and GitHub servers if
      they gain a log option.

### A3. Variable tiers (per repo)

Every Packer/OpenTofu variable belongs to exactly one tier, decided by
**who needs to decrypt it**:

| Tier | Contents | Storage | Committed? | Agent a recipient? |
| --- | --- | --- | --- | --- |
| 1. Shared secrets | Proxmox write tokens, password hash; anything both repos consume | `~/.secrets/homelab.yaml` | yes (encrypted) | **no** |
| 2. Repo-local, don't-publish | subnets, DNS IPs, internal endpoints, service usernames, SSH *public* keys | `environment.enc.yaml`, per repo | yes (encrypted) | **yes**, so the agent can dry-run |
| 3. Public-safe config | sizes, VM IDs, ISO paths, structural values | `*.pkrvars.hcl` / `*.tfvars` | yes (cleartext) | n/a |

A value both repos need is Tier 1, never copied into both
`environment.enc.yaml` files. The password hash is Tier 1 because it's
shared, and because keeping it out of anything agent-readable makes it
undecryptable by construction (a `$6$` hash can be cracked offline).

- [ ] Dry-run defaults: every Tier-1 variable gets a valid-shaped dummy
      `default` (`sensitive = true`), so `validate`/`plan` pass without
      the real value. Don't use `ignore_changes` to hide the dummy-vs-real
      diff; a plan against dummies is expected and never applied.
- [ ] `.sops.yaml` creation rules: `environment\.enc\.yaml$` encrypts to
      agent + CI + personal; `homelab\.yaml$` stays personal only (A4;
      the rule lives in `~/.secrets/.sops.yaml`).
- [ ] Loading: Tier-2 keys are named after the env vars (`PKR_VAR_*`,
      `TF_VAR_*`) like the Tier-1 files, and the `mise run` tasks nest a
      second `sops exec-env` for them, e.g.
      `sops exec-env ~/.secrets/homelab.yaml "sops exec-env environment.enc.yaml 'tofu plan'"`.
- [ ] **Core classification:**
      - Tier 1: `password_hash` (Packer).
      - Tier 2: `ssh_authorized_keys`, `proxmox_endpoint`, `gateway`,
        `nameserver`, `sshkeys`.
      - Tier 3: `target_node`, `vm_template`, `network_bridge`, `ciuser`,
        and the sizing/boolean variables.
      - Also check that `ssh_private_key_file` points outside the repo.
- [ ] **Workloads classification:** same exercise for its Terramate
      stacks.
- [ ] Done when: both repos pass `packer validate` / `tofu plan` on
      dummy defaults alone, and real secrets exist only in
      `~/.secrets/homelab.yaml` and CI.

### A4. Shared secret files

- [ ] CI gets its own committed `ci/dry-run.sops.yaml` (A1) rather than
      becoming a recipient of `~/.secrets/homelab.yaml`: the runner never
      holds the human's shared write credentials. The `ai-agent` key stays
      a recipient of `homelab-ro.yaml` and `ai-agent-git.yaml` only.
- [ ] Workloads reuses the same two files and the same `mise run`
      task pattern, adding its own keys rather than duplicating values.

### A5. Host shell hygiene

- [x] Confirm on the rebuilt workstation that nothing exports `PKR_VAR_*`,
      `TF_VAR_*` or `TF_TOKEN_*` into the shell (`~/.zshrc`, profile, mise
      env) — `docs/CREDENTIALS.md` step 7.

### A6. Devcontainer: repo-scoped dry-run harness (core and workloads)

The agent runs in a devcontainer that starts from an empty environment,
so it can't inherit the human's RW credentials from the shell. Use
the AI agent's Dev Container Feature
(`ghcr.io/anthropics/devcontainer-features/claude-code`).

- [ ] **Workloads:** the same devcontainer as core's (`.devcontainer/`,
      `docs/DEVCONTAINER.md`), adding Terramate, kubectl and Helm to its
      toolchain.
- [x] Core: run the checks in `docs/DEVCONTAINER.md` ("Prove the
      boundary") in the container and confirm each behaves as described.
- [ ] Close the credentials the Dev Containers extension passes in by
      default: no forwarded ssh-agent (`SSH_AUTH_SOCK` blank), no shared
      git credential helper (only the agent's own, A1), and no shared
      working copy: the agent works in its own clone, a separate WSL
      folder opened only with *Reopen in Container*, and the human runs
      credentialed tasks only from his own WSL clone, on merged code. Commits from the container run pre-commit through
      container-only hooks (`core.hooksPath`). `boundary:check` proves
      each one.

### A7. Ansible secrets: inventory-scoped SOPS (workloads)

`ansible-playbook --check --diff` still decrypts secrets to render
templates, so this file is encrypted to the main age recipient (and `ci`),
**never** to `ai-agent`. The agent's Ansible remit is `ansible-lint`,
`--syntax-check` and reading playbooks.

- [ ] **Workloads:** same pattern as core — `community.sops` vars plugin
      with `vars_stage = task`, per-group `group_vars/<group>.sops.yaml` —
      for the Elastic passwords, the Fleet enrollment token and its own
      Cloudflare token (Traefik).
- [ ] Ownership: the agent can do the wiring; putting real secret values
      in is a human edit.

### A8. Investigation MCPs: read-only by capability

Each MCP server is RO only if its credential or RBAC is RO. Prove it by
attempting a mutating call and confirming it's refused.

- [x] Core's three servers (Proxmox, GitHub, Terraform) set up per
      `docs/CREDENTIALS.md` step 8, with each negative test there
      passing.
- [ ] GitHub MCP: add **Issues: write** to its PAT only when Phase C
      starts filing issues; everything else stays read-only.
- [ ] Elastic MCP: API key with `cluster: [monitor]` and
      `indices: [*]: [read, view_index_metadata]`.
- [ ] Kubernetes MCP: a dedicated RO ServiceAccount and `ClusterRole`
      (`get`/`list`/`watch` only) with its own kubeconfig. The human's
      kubeconfig stays full-access.
- [ ] ArgoCD MCP: a dedicated RO account (ArgoCD gates read vs. sync only
      by RBAC):

      ```text
      p, role:ai-agent-ro, applications, get, */*, allow
      # deliberately NO: sync, delete, override, action/*
      ```

- [ ] A CI-specific ServiceAccount/ArgoCD account for the `ci` principal.

### A9. Telemetry coverage

- [ ] Fleet-managed Elastic Agent on every host in both repos, including
      core's `proxy` and `server01`. Core's Packer template already
      installs it (tarball via `elastic-agent install`, Fleet-upgradable,
      not enrolled, service disabled); what's
      left is an Ansible playbook that runs `elastic-agent enroll` with a
      Fleet enrollment token and enables the service. The CoreDNS and Pi-hole secondaries
      run in QNAP Container Station, outside Ansible: decide how their
      logs reach Elastic (an agent on the NAS, or shipping the container
      logs).
- [ ] CoreDNS metrics (`prometheus` plugin) and Caddy metrics/access logs
      into Elastic.
- [ ] K3s node/pod logs and metrics, including the cluster-wide
      `elastic-agent` preset (Fleet mode runs one preset per release, so
      `perNode` and `clusterWide` need separate releases).
- [ ] Auditd Manager on the Proxmox VMs: kernel-level ground truth for the
      Gold tier in Phase D.
- [ ] MCP server metrics: `terraform-mcp-server` emits tool-call counts,
      latency and failures as OpenTelemetry metrics when
      `OTEL_METRICS_ENABLED=true` (plus the standard `OTEL_EXPORTER_OTLP_*`
      endpoint settings). Turn it on in `.mcp.json` once there's an OTLP
      receiver (e.g. the Elastic stack's).

### A10. Dry-run executor: a self-hosted GitHub Actions runner

The agent can't dry-run against live state: `ansible-playbook --check`
needs the inventory secrets and root-equivalent SSH, and `tofu plan`
needs HCP state the Free plan can't share read-only (A1). The dry-runs
move to a runner on the LAN holding the `ci` principal. The agent opens a
PR, the human approves the `dry-run` environment, the runner dry-runs it,
and the agent reads the result. Apply stays human-only.

- [ ] `runner01` VM cloned from the `ubuntu-26.04` template by
      `terraform/` (inventory group `github_runner`), small (2 vCPU /
      4 GB / 40 GB), outbound-only: no inbound port, no Caddy site.
- [ ] `github_runner` Ansible role and `playbooks/30-github-runner.yml`
      (not in `site.yml`): pinned, checksum-verified runner as a systemd
      service, unprivileged `gha-runner` user (no sudo, not in `docker`,
      Docker service disabled), self-update on (the pin is only the
      first install), registers only when `.runner` is absent
      with the token from a private `vars_prompt` and `no_log`. Org-level
      runner group limited to the two homelab repos, label `homelab`.
      `mise run runner:check` proves the runner's limits.
- [ ] Core playbooks are check-mode safe: read-only `command`/`shell`/`uri`
      tasks get `check_mode: false` + `changed_when: false`, conditions on
      skipped results use `default(...)`, a pre-commit check lists every
      `check_mode: false` for review, and `site.yml` refuses a non-check
      run when `HOMELAB_DRY_RUN=1` (backstop only).
- [ ] mise tasks shared by CI and the human: `tofu:plan-ci` (never writes
      `tfplan`) and `ansible:check` (`--check --diff --limit
      '!github_runner'`), both with the `ci` key; denied to the agent.
- [ ] `.github/workflows/dry-run.yml`: `pull_request` only (never
      `pull_request_target`), same-repo PRs only, `environment: dry-run`
      with the human as required reviewer (the actual boundary),
      `contents: read`, one global concurrency group, `paths`-filtered
      `plan` and `check` jobs. Every action in every workflow pinned to a
      commit SHA; `actionlint` and `zizmor` in mise and pre-commit.
- [ ] Dry-run output kept off public logs (the repos are public): only
      the plan summary and the Ansible recap in the log and run summary;
      the full output age-encrypted to the human + `ai-agent` keys as a
      short-retention artifact (`docs/RUNNER.md`). `tfplan` is never
      uploaded.
- [ ] Runner telemetry: Elastic Agent enrolled (A9) and the runner's
      `_diag` logs shipped, feeding the audit trail (A2).
- [ ] Done when: a PR touching `terraform/` and `ansible/` gets a plan and
      a check recap after the human approves, a fork PR never reaches the
      runner, and `boundary:check` / `runner:check` pass.

Later, each only after the dry-run path has a track record:

- [ ] Port the dry-run workflow to `homelab-proxmox-workloads`
      (`terramate run --changed -- tofu plan`, its own check-mode fixes,
      the `pki` role skipped, a read-only Elasticsearch/Kibana API key for
      its `config` stacks).
- [ ] CI apply: a separate `apply` environment and `ci@pve!apply`
      (`TofuApply`).
- [ ] Ephemeral runners (JIT config, or ARC on the K3s cluster).
- [ ] Replace the long-lived HCP token in `ci/dry-run.sops.yaml` with
      GitHub Actions OIDC, after checking what HCP Terraform accepts for a
      Local-execution workspace.
- [ ] Codify the org rulesets with the GitHub provider
      (`github_organization_ruleset`).

## Phase B — Detection (L0 → L1)

- [ ] SLOs and error budgets first, so alerts page on user impact rather
      than raw anomalies. Starting set:
      - DNS resolution success and latency (CoreDNS `.2`/`.3`, Pihole
        `.5`/`.6`)
      - Caddy per-site availability and cert validity
      - ES cluster availability
      - OTel Demo checkout success rate
- [ ] Multi-window burn-rate alerts on those SLOs.
- [ ] Kibana rules for **core**: Caddy cert renewal failures,
      backend-unreachable errors, CoreDNS/Pihole query failures or
      upstream unreachability, primary/secondary drift (SOA serial `.2`
      vs `.3`; config `.5` vs `.6`), host resource pressure.
- [ ] Kibana rules for **workloads**: ES cluster yellow/red, node down,
      disk watermark, APM error rate and latency, host CPU/memory/disk,
      K3s node conditions (NotReady/DiskPressure/MemoryPressure), pod
      states (CrashLoopBackOff/ImagePullBackOff/OOMKilled), ArgoCD app
      health (OutOfSync/Degraded).
- [ ] Synthetic checks from a LAN vantage point, so detection doesn't
      depend only on the systems being monitored.

## Phase C — Assisted investigation (L1)

- [ ] **Trigger:** poll-based first, with a scheduled `ai-agent-scheduled`
      run that checks for active alerts via the Elastic MCP. Consider a
      push webhook receiver only after that works.
- [ ] **Alert enrichment** (the paper's AI Alert, read-only, small time
      budget): when an alert fires, query logs, metrics, recent changes
      (git log, ArgoCD sync history, HCP runs) and dependencies
      (DNS → Caddy → backend) in parallel, then attach a summary. No
      mitigation.
- [ ] **Investigation runbook** as an AI agent skill. Given an alert,
      fan out across the RO MCPs and produce Symptom → Evidence →
      Hypotheses considered → Probable cause → Recommended remediation →
      Confidence and blast radius. File it as a GitHub issue in the repo
      that owns the failing component.
- [ ] **Escalation:** when the cause can't be identified, or the component
      is outside the catalog, the issue says so plainly and is labelled
      for a human. No guessing at a fix.
- [ ] **Grounding:** the runbook reads both repos' `docs/`, previous
      incident issues and the topology map, so hypotheses rest on how this
      homelab actually works.
- [ ] **Topology map:** one machine-readable file listing each
      component's host, IP, owning repo, upstream and downstream.

## Phase D — Evaluation data and memory

- [ ] Data tiers:
      - **Bronze:** self-reported audit logs (A2).
      - **Silver:** structured incident issues from Phase C.
      - **Gold:** human-confirmed outcomes plus `auditd` ground truth.

      The WSL2 dev box has no `auditd`, so Bronze is its ceiling.
- [ ] **Golden data at incident close:** an issue template or closing
      checklist that records the mitigation actually applied and whether
      the agent's recommendation was right, partly right or wrong.
- [ ] **Fault-injection scenarios as the starting eval set:** break things
      on purpose in a controlled way and check that detection and
      investigation get it right. Candidates:
      - ACME DNS-01 with the wrong resolvers
      - a Caddy backend down
      - CoreDNS secondary out of sync
      - a full disk on a K3s node
      - a crash-looping deployment
      - a misconfigured Fleet output
- [ ] **Eval runs:** replay scenarios and real incidents against the
      runbook. Score the final recommendation deterministically (right
      cause, right action) and the investigation path with an LLM judge.
      Track precision per action type: this is the evidence for the
      L1 → L2 and L2 → L3 gates.

## Phase E — Approval-gated mitigation (L2)

- [ ] **Mitigation catalog:** a short list of named actions, each with
      parameters, a dry-run command, a verification check, a blast-radius
      note and a rollback. Examples:
      - restart one compose service
      - re-run one Ansible role with `--limit` on one host
      - `kubectl rollout restart` of one deployment
      - prune old images on one node
- [ ] **Executor separated from reasoner:** a small service that only
      accepts catalogued actions. It runs the dry run, checks that an open
      incident issue justifies the action, refuses concurrent actions on
      the same target, then executes and polls for verification. Runs as
      `ai-executor` with the minimal write grant each action needs.
- [ ] **Approval path:** the investigation issue proposes a catalogued
      action; the human approves with a comment or reaction.
- [ ] **Circuit breakers:** per-action and global rate limits, plus a stop
      after repeated failures on one target.
- [ ] **Red button:** a documented, tested procedure that revokes the
      executor's token and disables the scheduled trigger.
- [ ] **DNS/proxy guard:** no action may take down both halves of a
      primary/secondary pair (`.2`/`.3`, `.5`/`.6`) at once. Core
      components are the highest risk class.

## Phase F — Bounded autonomy (L3)

- [ ] Promote individual catalog actions to run without approval only
      after their own approval record clears the L2 → L3 gate.
      Candidates:
      - node disk-pressure cleanup (prune images, never reboot)
      - a bounded `kubectl scale` for one diagnosed recurring
        CrashLoopBackOff pattern
      - restarting one Caddy/CoreDNS/Pihole container whose healthcheck
        failed, when its pair partner is healthy
- [ ] Automatic downgrade to L2 when the risk check flags elevated risk:
      a deploy in progress, error budget exhausted, another open incident,
      or the pair partner unhealthy.
- [ ] Keep L3 strictly narrower than ArgoCD's `selfHeal`: bounded,
      rate-limited actions with their own verification, never open-ended
      reconciliation.

## Out of scope

- L4 (open-ended, multi-step autonomous incident handling).
- Any agent path to `packer build`, `tofu apply`/`destroy` or
  `ansible-playbook` against live hosts.
- Agents writing and deploying fixes. Code changes go through the normal
  PR flow, with a human merging.
