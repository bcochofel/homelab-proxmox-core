# GitHub

How the `BCochofelHomelab` organization and its two repositories,
`homelab-proxmox-core` and `homelab-proxmox-workloads`, are set up, and
why. All of it is configured by hand in GitHub's web UI; nothing in either
repo applies it. This page is the record: change a setting, change it here
too.

The AI agent has its own GitHub account, a machine user. It pushes
branches and opens pull requests; it never merges, approves or tags. Most
of that is enforced by GitHub, through the settings below. Two things
aren't, and only `.claude/settings.json` stops them: merging a pull
request you've already approved, and creating tags (see
[What GitHub enforces](#what-github-enforces-and-what-it-doesnt)). Its
token is set up in [`CREDENTIALS.md`](CREDENTIALS.md) step 9.

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
  any push after your approval needs a fresh one. Once you've approved,
  though, any user with Write can click merge, the machine user included:
  rulesets don't control who merges. Only `.claude/settings.json` stops
  the agent there, so **merge right after you approve**.
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
restricted, because semantic-release creates each release tag as
`github-actions[bot]` with the workflow's default token
(`.github/workflows/release.yml`). A tag the machine user pushed would
trigger nothing, but semantic-release computes the next version from the
existing tags, so a stray one would skew it: `.claude/settings.json`
denies the agent `git tag` and pushing tags.

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

## What GitHub enforces, and what it doesn't

Two controls together keep the machine user's work from running or
landing unreviewed. Each covers what the other can't:

| Control | When it acts | What it stops |
| --- | --- | --- |
| The token has **no Workflows permission** | At push | GitHub rejects any push that touches `.github/workflows/`, so an edited workflow never exists on GitHub to run. |
| **CODEOWNERS** + `protected-default` | At merge | Nothing reaches `main` without your review, including `mise.toml`, `.claude/settings.json` and `.devcontainer/`. |

The push-time control matters because a `pull_request` workflow runs the
workflow file from the pull request's branch, not from `main`. An edited
workflow would run before anyone reviewed it; CODEOWNERS alone can't
prevent that.

What GitHub doesn't stop, and `.claude/settings.json` does (a soft
boundary, so you act accordingly):

- **Merging after your approval.** You merge right after approving.
- **Creating tags.** `git tag` and tag pushes are denied.
- **Approving someone else's pull request.** Its approval never counts,
  since it isn't a code owner, and `gh pr review` is denied anyway.

### Why HTTPS, never SSH

The machine user pushes over HTTPS with its token, never with an SSH key
(the devcontainer rewrites SSH remotes to HTTPS):

- an SSH key can't be limited to two repositories or set to expire;
- the Workflows block applies only to token-based pushes: an SSH push can
  change `.github/workflows/`.

## Red button: stopping the AI agent

One procedure, for you only, to stop everything the AI agent can do on
GitHub. This page covers the agent; the runner's half will live with the
runner's own documentation.

### Level 1: pause (something looks wrong; reversible)

Do these in order. Each one cuts a path on its own, so a partial run
still helps.

1. **Its write access:** *Organization → Teams → `sre-team` → Members* →
   remove `bcochofel-ai-agent`. Its Write access ends at once, even with a
   valid token.
2. **Its session:** close the devcontainer window, or `docker stop
   <container>` from WSL. Claude Code and the MCP servers stop with it.

**Restore,** in reverse: reopen the devcontainer, add the machine user
back to `sre-team`, then run `mise run boundary:check` in the container.

### Level 2: revoke (a credential may have leaked)

Do Level 1 first, then:

| Identity | Revoke | Then rotate |
| --- | --- | --- |
| The machine user's token | *Organization settings → Personal access tokens → Active tokens* → revoke it (an owner can revoke any token that accesses the organization), or as the machine user | A new token in `~/.secrets/ai-agent-git.yaml` ([`CREDENTIALS.md`](CREDENTIALS.md) step 9) |
| The `ai-agent` age key | Remove it from `~/.secrets/.sops.yaml`, then `updatekeys` `homelab-ro.yaml` and `ai-agent-git.yaml` ([`CREDENTIALS.md`](CREDENTIALS.md) step 5) | Everything in those two files: the `ai-agent@pve` Proxmox token, the read-only GitHub token, the machine user's token |

Afterwards, run `mise run secrets:check`, `creds:check` and
`boundary:check`.

## GitHub CLI

`gh` is pinned in `mise.toml`, so the same version runs on WSL and in the
devcontainer. Who it acts as depends on where it runs.

### On WSL, as you

Log in once with your own account. The login is stored in
`~/.config/gh/hosts.yml` and used by every `gh` on WSL, inside the repo
(mise's) or outside it:

```bash
gh auth login --hostname github.com --git-protocol ssh --web
gh auth status    # account bcochofel; shows the token's scopes, never the token
```

`--web` opens a browser to authorize the GitHub CLI app; `--git-protocol
ssh` keeps your clone's `git@github.com` remote, pushed with your SSH key.
It requests the default scopes, `repo`, `read:org` and `gist`, which
cover pull requests and the read-only checks below. If the organization
settings in those checks come back as `null`, add the organization
scope:

```bash
gh auth refresh --scopes admin:org
```

The AI agent never uses this login: in its WSL sessions,
`.claude/settings.json` denies `gh auth` and every `gh` command that
merges, approves, releases or writes through `gh api`, and your clone's
`.claude/settings.local.json` makes it ask you before `git push` and
`gh pr create` ([`DEVCONTAINER.md`](DEVCONTAINER.md#pushes-and-pull-requests)).

### In the devcontainer, as `bcochofel-ai-agent`

Nothing to log in. `gh` there is `.devcontainer/bin/gh`, a wrapper first
on `PATH` that decrypts the machine user's token from
`~/.secrets/ai-agent-git.yaml` and passes it to that one `gh` process as
`GH_TOKEN`. There's no `hosts.yml`, and `gh auth login` must never be run
there. git uses the same token through
`.devcontainer/bin/git-credential-ai-agent`.

To check it, in the container's terminal:

```bash
gh auth status          # logged in as bcochofel-ai-agent, from GH_TOKEN
gh api user --jq .login # bcochofel-ai-agent
mise run boundary:check # every line ok, including the git and GitHub section
```

These are for you: the AI agent is denied `gh auth`, and runs
`boundary:check` itself.

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
