.PHONY: help check all install install-binaries install-python-tools install-node-tools \
		install-terraform install-terraform-docs install-trivy install-shellcheck install-tflint \
		install-lint-hooks run-semantic-release lint-all tflint-init setup-gitmessage \
		clean pkr-validate pkr-gen-vars-example pkr-gen-vars-docs pkr-build

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

PKR_TEMPLATE_DIRS := $(wildcard packer/*)
PKR_TEMPLATES := $(filter-out %/, $(PKR_TEMPLATE_DIRS))

help: ## Show this help message
	@echo "Usage: make [target]"
	@echo ""
	@echo "Available targets:"
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "  $(GREEN)%-25s$(NC) %s\n", $$1, $$2}'

check: ## Check system dependencies (Python and NodeJS versions)
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

all: install ## Install all dependencies

install: install-binaries install-python-tools install-node-tools install-lint-hooks tflint-init setup-gitmessage ## Install all dependencies
	@echo "✅ All tools and hooks installed successfully."

install-binaries: install-terraform install-terraform-docs install-trivy install-shellcheck install-tflint ## Install binaries

install-python-tools: ## Install Python dependencies
	@echo "Creating Python virtualenv at $(VENV_DIR)..."
	@python3 -m venv $(VENV_DIR)
	@$(VENV_DIR)/bin/pip install --upgrade pip
	@$(VENV_DIR)/bin/pip install -r requirements.txt
	@echo "Installed Python tools:"
	@$(VENV_DIR)/bin/pip list

install-node-tools: ## Install NodeJS dependencies
	@echo "Installing Node.js tools using npm ci..."
	@mkdir -p $(NODE_DIR)
	@cp package.json package-lock.json $(NODE_DIR)/
	@cd $(NODE_DIR) && npm ci
	@echo "Node tools installed in $(NODE_DIR)"

install-lint-hooks: ## Install pre-commit hooks
	@echo "Installing pre-commit hooks..."
	@$(VENV_DIR)/bin/pre-commit install --hook-type pre-commit
	@$(VENV_DIR)/bin/pre-commit install --hook-type commit-msg
	@echo "Hooks installed: pre-commit and commit-msg"

lint-all: ## Run pre-commit on all files
	@echo "Running pre-commit on all files..."
	@$(VENV_DIR)/bin/pre-commit run --all-files

run-semantic-release: ## Run semantic-release dry-run
	@$(NPM_BIN)/npx semantic-release --no-ci --dry-run

install-terraform: ## Install Terraform binary
	@echo "Installing Terraform $(TERRAFORM_VERSION)..."
	@mkdir -p $(BIN_DIR)
	@curl -sSL $(TERRAFORM_URL) -o /tmp/terraform.zip
	@unzip -o /tmp/terraform.zip -d $(BIN_DIR)
	@chmod +x $(BIN_DIR)/terraform
	@rm /tmp/terraform.zip
	@echo "Terraform installed at $(BIN_DIR)/terraform"

install-terraform-docs: ## Install terraform-docs binary
	@echo "Installing terraform-docs $(TERRAFORM_DOCS_VERSION)..."
	@mkdir -p $(BIN_DIR)
	@curl -sSL $(TERRAFORM_DOCS_URL) -o /tmp/terraform-docs.tar.gz
	@tar -xzf /tmp/terraform-docs.tar.gz -C /tmp
	@mv /tmp/terraform-docs $(BIN_DIR)/terraform-docs
	@chmod +x $(BIN_DIR)/terraform-docs
	@rm /tmp/terraform-docs.tar.gz
	@echo "terraform-docs installed at $(BIN_DIR)/terraform-docs"

install-trivy: ## Install trivy binary
	@echo "Installing Trivy $(TRIVY_VERSION)..."
	@mkdir -p $(BIN_DIR)
	@curl -sSL $(TRIVY_URL) -o /tmp/trivy.tar.gz
	@tar -xzf /tmp/trivy.tar.gz -C /tmp trivy
	@mv /tmp/trivy $(BIN_DIR)/trivy
	@chmod +x $(BIN_DIR)/trivy
	@rm /tmp/trivy.tar.gz
	@echo "Trivy installed at $(BIN_DIR)/trivy"

install-shellcheck: ## Install shellcheck binary
	@echo "Installing ShellCheck $(SHELLCHECK_VERSION)..."
	@mkdir -p $(BIN_DIR)
	@curl -sSL $(SHELLCHECK_URL) -o /tmp/shellcheck.tar.xz
	@tar -xf /tmp/shellcheck.tar.xz -C /tmp
	@mv /tmp/shellcheck-v$(SHELLCHECK_VERSION)/shellcheck $(BIN_DIR)/shellcheck
	@chmod +x $(BIN_DIR)/shellcheck
	@rm -rf /tmp/shellcheck.tar.xz /tmp/shellcheck-v$(SHELLCHECK_VERSION)
	@echo "ShellCheck installed at $(BIN_DIR)/shellcheck"

install-tflint: ## Install TFLint binary
	@echo "Installing TFLint $(TFLINT_VERSION)..."
	@mkdir -p $(BIN_DIR)
	@curl -sSL $(TFLINT_URL) -o /tmp/tflint.zip
	@unzip -o /tmp/tflint.zip -d $(BIN_DIR)
	@chmod +x $(BIN_DIR)/tflint
	@rm /tmp/tflint.zip
	@echo "TFLint installed at $(BIN_DIR)/tflint"

tflint-init: ## Initialize TFLint
	@echo "Initializing TFLint rulesets..."
	@$(BIN_DIR)/tflint --init
	@echo "TFLint rulesets installed."

setup-gitmessage: ## Setup Git commit message template
	@echo "Setting up commit message template..."
	@git config commit.template $(GITMESSAGE_FILE)
	@echo "Git commit.template set to $(GITMESSAGE_FILE)"

clean: ## Cleanup
	@rm -rf /tmp/terraform.zip /tmp/terraform-docs.tar.gz /tmp/trivy.tar.gz \
		/tmp/shellcheck.tar.xz /tmp/shellcheck-v$(SHELLCHECK_VERSION) /tmp/tflint.zip
	@echo "Cleaned temporary files."

pkr-validate: ## Packer: validate all templates
	@for tmpl in $(PKR_TEMPLATES); do \
		if [ -d $$tmpl ] && ls $$tmpl/*.pkr.hcl >/dev/null 2>&1; then \
			echo "==> Validating template: $$tmpl"; \
			$(MAKE) -C $$tmpl validate; \
		fi \
	done

pkr-gen-vars-example: ## Packer: Generate example variables file
	@for tmpl in $(PKR_TEMPLATES); do \
		if [ -d $$tmpl ] && [ -f $$tmpl/variables.pkr.hcl ]; then \
			echo "==> Generating example vars for: $$tmpl"; \
			$(MAKE) -C $$tmpl gen-example-vars; \
		fi \
	done

pkr-gen-vars-docs: ## Packer: Update README.md table of vars for each template
	@for tmpl in $(PKR_TEMPLATES); do \
		if [ -d $$tmpl ] && [ -f $$tmpl/variables.pkr.hcl ]; then \
			echo "==> Generating example vars docs for: $$tmpl"; \
			$(MAKE) -C $$tmpl docs; \
		fi \
	done

pkr-build: ## Packer: Build templates
	@for tmpl in $(PKR_TEMPLATE); do \
		echo ""; \
		echo "==> Building template: $$tmpl"; \
		$(MAKE) -C $$tmpl build || exit 1; \
	done
