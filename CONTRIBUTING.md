# Contributing

Thanks for working on this repo. Start with [`README.md`](README.md) for
what this project is and its Quickstart section to get both VMs running
end to end. This doc covers the contributor workflow: environment setup,
branching, commit conventions, versioning, and the shift-left checks that
run before code lands.

## Local environment setup

Prerequisite: [mise](https://mise.jdx.dev) (activated in your shell, see
`mise activate --help`). Everything else is pinned in [`mise.toml`](mise.toml):

```bash
mise trust && mise install
```

This is the one command a new contributor needs: it installs every pinned
tool (`packer`, OpenTofu's `tofu`, `terraform` (pinned only as a rollback
path), `terramate`, `tflint`, `terraform-docs`, `trivy`, `gitleaks`,
`checkov`, `sops`, `age`, `pre-commit`, plus the Python, uv and Node
runtimes), creates the Python virtualenv (`.venv/`) Ansible runs from,
and then runs `mise run bootstrap` automatically: installs Ansible and its
required collections into `.venv/`, downloads the TFLint rulesets, installs
the pre-commit git hooks (see below) and sets the commit message template.
Credentials are set up separately — see
[`docs/CREDENTIALS.md`](docs/CREDENTIALS.md).

`mise.lock` and `.mise/locks/` record the exact version and checksum of
every tool; CI installs from them in locked mode, so laptops and CI run
identical versions. To bump a tool: `mise run outdated`, edit the pin in
`mise.toml`, run `mise lock`, and commit all three together.

Run `mise tasks` to see every available task; `mise run doctor` shows
what's currently installed and detected.

## Shift-left feedback: pre-commit

`mise install` runs `mise run setup:hooks`, which registers the git hooks
(both the `pre-commit` and `commit-msg` stages) for you — nothing extra to
do per clone. To (re-)run it standalone:

```bash
mise run setup:hooks
```

From then on, `git commit` runs the checks in [`.pre-commit-config.yaml`](.pre-commit-config.yaml)
automatically. You can also run everything on demand:

```bash
mise run lint      # pre-commit run --all-files
mise run check     # the above + full-history gitleaks scan (what CI runs)
```

What runs:

- **General file hygiene** — end-of-file-fixer, trailing-whitespace,
  detect-private-key, check-merge-conflict, no-commit-to-branch (blocks
  direct commits to `main`/`master`).
- **Packer** (when a `packer/**/*.pkr.hcl` or `*.pkrvars.hcl` file
  changes) — `packer fmt -check` and `packer validate -syntax-only` against
  every template directory under `packer/`.
- **Terraform** (files under `terraform/`) — `tofu fmt`,
  `tofu validate`, `terraform-docs` (keeps `terraform/README.md`'s
  generated table in sync), TFLint, Trivy, and Checkov, using the configs at
  the repo root (`.tflint.hcl`, `.trivy.yaml`, `.trivyignore`,
  `checkov.yaml`).
- **Markdown** (all `*.md` files) — `markdownlint-cli2`, using
  `.markdownlint.yaml` at the repo root.
- **Ansible** (files under `ansible/`) — `ansible-lint`, run from `ansible/`
  through the project's own `.venv/`. SOPS-encrypted
  `inventory/group_vars/*.sops.yaml` files are excluded
  (`ansible/.ansible-lint`).
- **Secrets** — `gitleaks` on staged changes, using `.gitleaks.toml`
  (SOPS-encrypted files and lockfiles are allowlisted). `mise run secrets`
  scans the full git history.
- **Commit messages** — commitlint, at the `commit-msg` stage, checking
  against Conventional Commits (see below).

## Branching strategy

[Trunk-based development](https://trunkbaseddevelopment.com/): `main` is
the trunk.

- `main` is the stable branch — always deployable, the base for PRs.
- Day-to-day work happens on short-lived branches, opened as a PR against
  `main` and deleted after merge.

Branch names follow [Conventional Branch](https://conventionalbranch.org/)
1.1.0, `<prefix>/<description>`:

| Prefix | For |
| --- | --- |
| `feature/` (or `feat/`) | new capability |
| `bugfix/` (or `fix/`) | bug fix |
| `hotfix/` | urgent fix |
| `release/` | release preparation |
| `chore/` | non-code work: dependencies, docs, tooling |

- Lowercase letters, numbers and hyphens only (`feature/caddy-access-logs`);
  no spaces, underscores, uppercase, or leading/trailing/double hyphens.
  Dots only in release versions (`release/v5.1.0`).
- Branches created by an AI agent may use the spec's agent prefixes
  instead, e.g. `claude/` for Claude Code.
- Keep the branch prefix and the commit type in line: a `feature/` branch
  normally carries `feat:` commits.

Only `main` releases — it's the sole entry in the `branches` config in
[`.releaserc.js`](.releaserc.js). Other branches never cut prereleases.

## Commit messages (Conventional Commits)

Commit messages are linted by commitlint
([`commitlint.config.js`](commitlint.config.js)) against
[Conventional Commits](https://www.conventionalcommits.org/):

```text
<type>(optional scope): <subject>
```

Allowed types: `feat`, `fix`, `docs`, `style`, `refactor`, `perf`, `test`,
`build`, `ci`, `chore`, `revert` — the commit type drives the version bump
(see Versioning below).

`mise run setup:hooks` (part of `mise install`) wires up the repo's commit
template, so `git commit` (no `-m`) opens with the format and examples
pre-filled.

## Versioning & releases

This repo uses [semantic-release](https://semantic-release.gitbook.io/)
to compute the next version from commit history and cut a release — no
manual version bumps.

- `fix:` commits -> patch release
- `feat:` commits -> minor release
- A breaking change -> major release, marked either with `!` after the
  type/scope (`feat!:`, `refactor(tooling)!:`) or a `BREAKING CHANGE:`
  footer (any type)
- `docs:`, `chore:`, `style:`, etc. -> no release by themselves

On release, semantic-release ([`.releaserc.js`](.releaserc.js)) analyzes
commits and publishes a GitHub Release with the generated notes as its
body — no `CHANGELOG.md` file, and no commit back to the branch.
`.github/workflows/release.yml` runs this automatically on push to `main`,
using the default `GITHUB_TOKEN` (no PAT, no branch-ruleset bypass needed,
since nothing is pushed to `main`).

## Pull requests

- Keep PRs scoped to one logical change.
- `tofu fmt`/`tofu validate` and `packer fmt`/`packer validate` must pass
  before requesting review — all four run as pre-commit hooks, and in CI
  (`mise run check`).
- Actual `tofu apply` / `packer build` / `ansible-playbook` runs against
  real infrastructure are not part of pre-commit or this contributing flow —
  see the tool-specific docs under `docs/` for how those are run and gated.
