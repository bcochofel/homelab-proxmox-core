# Cross-platform Makefile for installing dev tools with reproducibility and CI/CD in mind

REQUIRED_NODE_VERSION := 20.18.0
REQUIRED_PYTHON_VERSION := 3.8.0

BIN_DIR := $(HOME)/bin
VENV_DIR := .venv
NODE_DIR := .node_modules
NPM_BIN := $(NODE_DIR)/node_modules/.bin

TERRAFORM_VERSION := 1.13.4
TERRAFORM_DOCS_VERSION := 0.20.0
TRIVY_VERSION := 0.67.2
SHELLCHECK_VERSION := 0.11.0
TFLINT_VERSION := 0.59.1

OS := $(shell uname -s)
OS_LOWER := $(shell uname -s | tr A-Z a-z)
ARCH := $(shell uname -m | sed 's/x86_64/amd64/;s/aarch64/arm64/')
ARCH_ORIG := $(shell uname -m)
GITMESSAGE_FILE=.gitmessage

TERRAFORM_URL := https://releases.hashicorp.com/terraform/$(TERRAFORM_VERSION)/terraform_$(TERRAFORM_VERSION)_$(OS_LOWER)_$(ARCH).zip
TERRAFORM_DOCS_URL := https://github.com/terraform-docs/terraform-docs/releases/download/v$(TERRAFORM_DOCS_VERSION)/terraform-docs-v$(TERRAFORM_DOCS_VERSION)-$(OS_LOWER)-$(ARCH).tar.gz
TRIVY_URL := https://github.com/aquasecurity/trivy/releases/download/v$(TRIVY_VERSION)/trivy_$(TRIVY_VERSION)_$(OS)-64bit.tar.gz
SHELLCHECK_URL := https://github.com/koalaman/shellcheck/releases/download/v$(SHELLCHECK_VERSION)/shellcheck-v$(SHELLCHECK_VERSION).$(OS_LOWER).$(ARCH_ORIG).tar.xz
TFLINT_URL := https://github.com/terraform-linters/tflint/releases/download/v$(TFLINT_VERSION)/tflint_$(OS_LOWER)_$(ARCH).zip

.PHONY: check all install install-binaries install-python-tools install-node-tools \
		install-terraform install-terraform-docs install-trivy install-shellcheck install-tflint \
		install-lint-hooks run-semantic-release lint-all tflint-init setup-gitmessage \
		clean help

check:
	@echo "🔍 Checking system dependencies..."

	@echo "Checking Python version..."
	@PYTHON_VERSION=$$(python3 -c 'import sys; print(".".join(map(str, sys.version_info[:3])))'); \
	if [ "$$(printf '%s\n' $(REQUIRED_PYTHON_VERSION) $$PYTHON_VERSION | sort -V | head -n1)" != "$(REQUIRED_PYTHON_VERSION)" ]; then \
		echo "❌ Python $$PYTHON_VERSION is too old. Required: $(REQUIRED_PYTHON_VERSION) or higher."; \
		exit 1; \
	else \
		echo "✅ Python $$PYTHON_VERSION meets requirement."; \
	fi

	@echo "Checking Node.js version..."
	@NODE_VERSION=$$(node -v | sed 's/v//'); \
	if [ "$$(printf '%s\n' $(REQUIRED_NODE_VERSION) $$NODE_VERSION | sort -V | head -n1)" != "$(REQUIRED_NODE_VERSION)" ]; then \
		echo "❌ Node.js $$NODE_VERSION is too old. Required: $(REQUIRED_NODE_VERSION) or higher."; \
		exit 1; \
	else \
		echo "✅ Node.js $$NODE_VERSION meets requirement."; \
	fi

all: install

install: install-binaries install-python-tools install-node-tools install-lint-hooks tflint-init setup-gitmessage
	@echo "✅ All tools and hooks installed successfully."

install-binaries: install-terraform install-terraform-docs install-trivy install-shellcheck install-tflint

install-python-tools:
	@echo "Creating Python virtualenv at $(VENV_DIR)..."
	@python3 -m venv $(VENV_DIR)
	@$(VENV_DIR)/bin/pip install --upgrade pip
	@$(VENV_DIR)/bin/pip install -r requirements.txt
	@echo "Installed Python tools:"
	@$(VENV_DIR)/bin/pip list

install-node-tools:
	@echo "Installing Node.js tools using npm ci..."
	@mkdir -p $(NODE_DIR)
	@cp package.json package-lock.json $(NODE_DIR)/
	@cd $(NODE_DIR) && npm ci
	@echo "Node tools installed in $(NODE_DIR)"

install-lint-hooks:
	@echo "Installing pre-commit hooks..."
	@$(VENV_DIR)/bin/pre-commit install --hook-type pre-commit
	@$(VENV_DIR)/bin/pre-commit install --hook-type commit-msg
	@echo "Hooks installed: pre-commit and commit-msg"

lint-all:
	@echo "Running pre-commit on all files..."
	@$(VENV_DIR)/bin/pre-commit run --all-files

run-semantic-release:
	@$(NPM_BIN)/npx semantic-release --no-ci --dry-run

install-terraform:
	@echo "Installing Terraform $(TERRAFORM_VERSION)..."
	@mkdir -p $(BIN_DIR)
	@curl -sSL $(TERRAFORM_URL) -o /tmp/terraform.zip
	@unzip -o /tmp/terraform.zip -d $(BIN_DIR)
	@chmod +x $(BIN_DIR)/terraform
	@rm /tmp/terraform.zip
	@echo "Terraform installed at $(BIN_DIR)/terraform"

install-terraform-docs:
	@echo "Installing terraform-docs $(TERRAFORM_DOCS_VERSION)..."
	@mkdir -p $(BIN_DIR)
	@curl -sSL $(TERRAFORM_DOCS_URL) -o /tmp/terraform-docs.tar.gz
	@tar -xzf /tmp/terraform-docs.tar.gz -C /tmp
	@mv /tmp/terraform-docs $(BIN_DIR)/terraform-docs
	@chmod +x $(BIN_DIR)/terraform-docs
	@rm /tmp/terraform-docs.tar.gz
	@echo "terraform-docs installed at $(BIN_DIR)/terraform-docs"

install-trivy:
	@echo "Installing Trivy $(TRIVY_VERSION)..."
	@mkdir -p $(BIN_DIR)
	@curl -sSL $(TRIVY_URL) -o /tmp/trivy.tar.gz
	@tar -xzf /tmp/trivy.tar.gz -C /tmp trivy
	@mv /tmp/trivy $(BIN_DIR)/trivy
	@chmod +x $(BIN_DIR)/trivy
	@rm /tmp/trivy.tar.gz
	@echo "Trivy installed at $(BIN_DIR)/trivy"

install-shellcheck:
	@echo "Installing ShellCheck $(SHELLCHECK_VERSION)..."
	@mkdir -p $(BIN_DIR)
	@curl -sSL $(SHELLCHECK_URL) -o /tmp/shellcheck.tar.xz
	@tar -xf /tmp/shellcheck.tar.xz -C /tmp
	@mv /tmp/shellcheck-v$(SHELLCHECK_VERSION)/shellcheck $(BIN_DIR)/shellcheck
	@chmod +x $(BIN_DIR)/shellcheck
	@rm -rf /tmp/shellcheck.tar.xz /tmp/shellcheck-v$(SHELLCHECK_VERSION)
	@echo "ShellCheck installed at $(BIN_DIR)/shellcheck"

install-tflint:
	@echo "Installing TFLint $(TFLINT_VERSION)..."
	@mkdir -p $(BIN_DIR)
	@curl -sSL $(TFLINT_URL) -o /tmp/tflint.zip
	@unzip -o /tmp/tflint.zip -d $(BIN_DIR)
	@chmod +x $(BIN_DIR)/tflint
	@rm /tmp/tflint.zip
	@echo "TFLint installed at $(BIN_DIR)/tflint"

tflint-init:
	@echo "Initializing TFLint rulesets..."
	@$(BIN_DIR)/tflint --init
	@echo "TFLint rulesets installed."

setup-gitmessage:
	@echo "Setting up commit message template..."
	@git config commit.template $(GITMESSAGE_FILE)
	@echo "Git commit.template set to $(GITMESSAGE_FILE)"

clean:
	@rm -rf /tmp/terraform.zip /tmp/terraform-docs.tar.gz /tmp/trivy.tar.gz \
		/tmp/shellcheck.tar.xz /tmp/shellcheck-v$(SHELLCHECK_VERSION) /tmp/tflint.zip
	@echo "Cleaned temporary files."

help:
	@echo "Usage:"
	@echo "	 make install                Install all tools and hooks"
	@echo "	 make install-binaries       Install Terraform, terraform-docs, Trivy, ShellCheck, TFLint"
	@echo "	 make install-python-tools   Install Python tools from requirements.txt"
	@echo "	 make install-node-tools     Install Node tools from package.json"
	@echo "	 make install-lint-hooks     Install Git hooks for pre-commit and commit-msg"
	@echo "	 make lint-all               Run pre-commit on all files"
	@echo "	 make run-semantic-release   Run semantic-release"
	@echo "	 make tflint-init            Install TFLint rulesets"
	@echo "	 make clean                  Remove temporary files"
