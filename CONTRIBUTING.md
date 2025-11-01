# 🛠️ Contributing to This Repository

Welcome! We're excited you're here and appreciate your interest in contributing.
This guide will help you get set up, follow our development standards, and submit high-quality contributions.

---

## 📦 Prerequisites

Before you begin, make sure you have:

- **Python 3.8+**
- **Node.js >=20.18.0**
- **Git**
- **Make**
- **pip** and **npm** installed globally

---

## 🚀 Getting Started

Clone the repository and install all development tools and hooks:

```bash
git clone <your-repo-url>
cd <your-repo-name>
make install
```

This will:

- Install Python dependencies in a virtual environment (`.venv`)
- Install Node.js tools in `.node_modules`
- Install binaries like Terraform, terraform-docs, Trivy, ShellCheck, and TFLint
- Set up Git commit message template
- Install pre-commit and commit-msg hooks

---

## 🧪 Development Workflow

### 1. Create a new branch

```bash
git checkout -b feature/my-awesome-change
```

### 2. Make your changes

Follow project structure and coding standards.

### 3. Run linters and security checks

```bash
make lint-all
```

This runs all pre-commit hooks including:

- YAML, Markdown, Shell, and Terraform linters
- Ansible linting
- Trivy and Checkov for security scanning
- EditorConfig validation
- Secret detection and merge conflict checks

### 4. Commit your changes

Use [Conventional Commits](https://www.conventionalcommits.org/) format:

```bash
git commit
```

You'll see a pre-filled `.gitmessage` template. Follow this format:

```txt
<type>(optional scope): <subject>

[optional body]

[optional footer]
```

#### ✅ Examples

- `feat(terraform): add s3 backend config`
- `fix(network): resolve DNS resolution issue`
- `docs: update README with setup instructions`

#### 🔧 Allowed types

`feat`, `fix`, `docs`, `style`, `refactor`, `perf`, `test`, `build`, `ci`, `chore`, `revert`

### 5. Push and open a pull request

```bash
git push origin feature/my-awesome-change
```

Then open a PR and follow the template.

---

## 🧹 Cleaning Up

To remove temporary files:

```bash
make clean
```

---

## 📦 Releasing

To simulate a release:

```bash
make run-semantic-release
```

This uses `semantic-release` to generate changelogs and version bumps based on commit history.

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

## 🤝 Code of Conduct

Please be respectful and inclusive. We follow the [Contributor Covenant](https://www.contributor-covenant.org/) Code of Conduct.

---

## 🙋 Need Help?

Open an issue or start a discussion. We're happy to support you!
