# 🛠️ Contributing to This Repository

Welcome! We're excited you're here and appreciate your interest in contributing. This guide will help you get set up, follow our development standards, and submit high-quality contributions.

---

## 📦 Prerequisites

Before you begin, make sure you have:

- **Python 3.8+**
- **Node.js ≥ 20.18.0**
- **Git**
- **Make**
- **pip** and **npm** installed globally

---

## 🚀 Getting Started

To set up your development environment automatically, run:

```bash
make check
make install
```

This script will:

- Run `make check` to verify system dependencies
- Run `make install` to install all tools, binaries, and Git hooks

Activate the Python virtual environment (`.venv`)

```bash
./setup.sh
```

Once activated, you're ready to start coding!

If you prefer manual setup, you can run:

```bash
make check
make install
source .venv/bin/activate
```

---

## 🧪 Development Workflow

### Create a new branch

```bash
git checkout -b feature/my-awesome-change
```

### Make your changes

### Run linters and security checks

```bash
make lint-all
```

### Commit your changes using Conventional Commits

```bash
git commit
```

You'll see a pre-filled `.gitmessage` template. Use this format:

```txt
<type>(optional scope): <subject>

[optional body]

[optional footer]
```

**Examples:**

- `feat(terraform): add s3 backend config`
- `fix(network): resolve DNS resolution issue`
- `docs: update README with setup instructions`

**Allowed types:** `feat`, `fix`, `docs`, `style`, `refactor`, `perf`, `test`, `build`, `ci`, `chore`, `revert`

### Push and open a pull request

```bash
git push origin feature/my-awesome-change
```

---

## 🧰 Tooling Summary

| Tool            | Purpose                                  |
|-----------------|-------------------------------------------|
| `pre-commit`    | Git hooks for linting and security checks |
| `commitlint`    | Enforces Conventional Commits             |
| `terraform-docs`| Auto-generates Terraform module docs      |
| `trivy`         | Scans Terraform for vulnerabilities       |
| `checkov`       | Static analysis for IaC security          |
| `shellcheck`    | Shell script linting                      |
| `yamllint`      | YAML file validation                      |
| `ansible-lint`  | Linting for Ansible playbooks             |

---

## 🧹 Cleaning Up

To remove temporary files:

```bash
make clean
```

To reset pre-commit environments:

```bash
make clean-pre-commit
```

---

## 📦 Releasing

To simulate a release:

```bash
make run-semantic-release
```

This uses `semantic-release` to generate changelogs and version bumps based on commit history.

---

## 🤝 Code of Conduct

Please be respectful and inclusive. We follow the [Contributor Covenant](https://www.contributor-covenant.org/) Code of Conduct.

---

## 🙋 Need Help?

Open an issue or start a discussion. We're happy to support you!
