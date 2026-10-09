# GitHub

How the `BCochofelHomelab` organization and its two repositories,
`homelab-proxmox-core` and `homelab-proxmox-workloads`, are set up, and
why. All of it is configured by hand in GitHub's web UI; nothing in either
repo applies it. This page is the record: change a setting, change it here
too.

The AI agent has its own GitHub account, a machine user. It pushes
branches and opens pull requests; it never merges, approves or tags. The
settings below are what enforce that, not the agent's own rules
(`.claude/settings.json` only adds a second layer). Its token is set up in
[`CREDENTIALS.md`](CREDENTIALS.md) step 9.

## Organization

The organization is on GitHub's **Free** plan. That's why the rulesets
below are per repository: organization-level rulesets need GitHub Team.

*Settings → Member privileges:*

| Setting | Value | Why |
| --- | --- | --- |
| Base permissions | Read | Members get repo access only through a team. |
| Repository creation | Off | The machine user can't create repositories. |
| Allow members to create teams | Off | Teams, and what they can reach, are set by an owner. |

*Settings → Authentication security:* two-factor authentication is
**required** for every member, the machine user included.

*Settings → Personal access tokens:* fine-grained tokens are allowed, and
each one needs an owner's approval before it can access the organization.

## Members

| Account | Org role | Who |
| --- | --- | --- |
| `bcochofel` | Owner | You |
| `bcochofel-ai-agent` | Member | The AI agent's machine user |

## Teams

Two teams, both *closed* (visible to every member), both with **Write** on
both repositories:

| Team | Members | Purpose |
| --- | --- | --- |
| `sre-team` | `bcochofel` (maintainer), `bcochofel-ai-agent` | Who can push branches and open pull requests. |
| `sre-lead` | `bcochofel` (maintainer) | Who reviews: the code owner of every file. |

Repository access comes only from these teams; `bcochofel-ai-agent` has
no direct grant on either repository. `sre-lead` needs Write: GitHub
ignores a CODEOWNERS team without at least Write on the repository.

The machine user must never be in `sre-lead`: its approval would then
count as a code owner's.

## Repositories

Both are public, with `main` as the default branch. *Settings → General
→ Pull Requests:* merge commits, squash and rebase merging are all
allowed (`protected-default` requires linear history, so a merge commit
is refused anyway), and **Automatically delete head branches** is on, so
a branch is gone once its pull request merges.

## CODEOWNERS

`.github/CODEOWNERS` in each repository:

```text
* @BCochofelHomelab/sre-lead
```

Every file is owned by `sre-lead`, including `CODEOWNERS` itself. Never
assign a path to `sre-team`: the machine user is in it, so it could
approve changes to that path.

CODEOWNERS doesn't stop anyone pushing a change to a branch. It decides
who must approve the pull request before the change can reach `main`
(the `protected-default` ruleset requires a code owner's review).

## Rulesets

Each repository has the same two rulesets (*Settings → Rules →
Rulesets*), both *Active*.

### `protected-default`

Target: the default branch (`main`).

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

Bypass list: the **Repository admin** role, mode **For pull requests
only**.

What this means:

- Nothing reaches `main` except through a pull request, for anyone.
- The machine user's pull requests need your approval as `sre-lead`, and
  any push after your approval needs a fresh one. It can't merge its own
  work.
- Your own pull requests: GitHub never lets you approve your own pull
  request, so you merge them with the admin bypass (the merge button
  offers to merge without waiting for the requirements). *For pull
  requests only* keeps that bypass on the pull request: you still can't
  push straight to `main`.

### `protected-tags`

Target: all tags.

| Rule | Setting |
| --- | --- |
| Restrict deletions | On |
| Block force pushes | On |

Bypass list: the **Repository admin** role, mode *Always*.

Tags can't be moved or deleted once they exist. Creating them isn't
restricted: semantic-release creates each release tag as
`github-actions[bot]` with the workflow's default token
(`.github/workflows/release.yml`), and a tag the machine user pushes
triggers nothing, since releases run only on pushes to `main`.

## The machine user's token

A fine-grained personal access token owned by `bcochofel-ai-agent`, for
the two repositories only:

| Permission | Access |
| --- | --- |
| Contents | Read and write |
| Pull requests | Read and write |
| Actions | Read |
| Issues | Read |
| Metadata | Read |
| Everything else (Workflows, Administration, Secrets, Environments, ...) | No access |

Without Workflows, GitHub rejects any push from it that changes
`.github/workflows/`, so workflow changes stay yours. Fine-grained tokens
offer no Checks permission. Creating,
storing and rotating it: [`CREDENTIALS.md`](CREDENTIALS.md) step 9.

## Check it

Read-only calls, as yourself (`gh` logged in as an organization owner):

```bash
o=BCochofelHomelab
# Organization: base permission and repository creation
gh api orgs/$o --jq '{default_repository_permission, members_can_create_repositories, members_can_create_teams, two_factor_requirement_enabled}'
# Teams, their members, and their access to each repository
for t in sre-lead sre-team; do
  echo "== $t: $(gh api orgs/$o/teams/$t/members --jq '.[].login' | paste -sd, -)"
  gh api orgs/$o/teams/$t/repos --jq '.[] | "  \(.name): \(.role_name)"'
done
# Each repository: collaborators (direct and through teams), rulesets, CODEOWNERS errors
for r in homelab-proxmox-core homelab-proxmox-workloads; do
  echo "== $r"
  gh api repos/$o/$r/collaborators --jq '.[] | "  \(.login): \(.role_name)"'
  for id in $(gh api repos/$o/$r/rulesets --jq '.[].id'); do
    gh api repos/$o/$r/rulesets/$id | jq -c '{name, enforcement, bypass_actors, rules: [.rules[] | {type, parameters}]}'
  done
  gh api repos/$o/$r/codeowners/errors --jq '.errors'
done
```

**Expect:** the values in the tables above; `bcochofel-ai-agent` at
`write` (through `sre-team`) and nothing more; `[]` for CODEOWNERS errors.

`mise run creds:check` checks the machine user's side: its token is
`bcochofel-ai-agent`'s, and can push to both repositories but not
administer them ([`CREDENTIALS.md`](CREDENTIALS.md) step 7.6).
