.PHONY: help debug check install install-binaries \
		install-terraform install-terraform-docs install-trivy install-tflint install-packer install-sops \
		clean direnv-allow pre-commit-install \
		packer-init tf-init venv ansible-install ansible-deps

# Makefile for installing/updating local CLI binaries into $(BIN_DIR),
# and for driving the Packer -> Terraform -> Ansible pipeline.
#
# `make install` is the shift-left entry point: it prepares everything a
# contributor needs to work in this repo (pinned binaries, direnv approval,
# pre-commit hooks, the Ansible virtualenv + collections). The pre-commit,
# checkov, direnv, and age binaries themselves are deliberately OUT of scope —
# those come from the OS package manager, not here.

# Pipeline directories
PACKER_DIR := packer/ubuntu-26.04
TERRAFORM_DIR := terraform
ANSIBLE_DIR := ansible

# Python virtualenv used to run Ansible (kept isolated from the system/OS Python)
VENV_DIR := $(CURDIR)/.venv

# Tool versions - Update these to get latest releases
TERRAFORM_VERSION := 1.15.8
TERRAFORM_DOCS_VERSION := 0.24.0
TRIVY_VERSION := 0.72.0
TFLINT_VERSION := 0.64.0
PACKER_VERSION := 1.16.0
SOPS_VERSION := 3.13.3

# Directory variables
BIN_DIR := $(HOME)/bin

# System detection with improved handling
UNAME_S := $(shell uname -s)
UNAME_M := $(shell uname -m)

# Normalize OS name
ifeq ($(UNAME_S),Linux)
	OS := Linux
	OS_LOWER := linux
else ifeq ($(UNAME_S),Darwin)
	OS := Darwin
	OS_LOWER := darwin
else ifeq ($(findstring MINGW,$(UNAME_S)),MINGW)
	OS := Windows
	OS_LOWER := windows
else ifeq ($(findstring MSYS,$(UNAME_S)),MSYS)
	OS := Windows
	OS_LOWER := windows
else
	OS := $(UNAME_S)
	OS_LOWER := $(shell echo $(UNAME_S) | tr A-Z a-z)
endif

# Normalize architecture
ifeq ($(UNAME_M),x86_64)
	ARCH := amd64
	ARCH_ORIG := x86_64
else ifeq ($(UNAME_M),amd64)
	ARCH := amd64
	ARCH_ORIG := amd64
else ifeq ($(UNAME_M),aarch64)
	ARCH := arm64
	ARCH_ORIG := aarch64
else ifeq ($(UNAME_M),arm64)
	ARCH := arm64
	ARCH_ORIG := arm64
else ifeq ($(UNAME_M),armv7l)
	ARCH := arm
	ARCH_ORIG := armv7l
else ifeq ($(UNAME_M),i386)
	ARCH := 386
	ARCH_ORIG := i386
else ifeq ($(UNAME_M),i686)
	ARCH := 386
	ARCH_ORIG := i686
else
	ARCH := $(UNAME_M)
	ARCH_ORIG := $(UNAME_M)
endif

# Download URLs
TERRAFORM_URL := https://releases.hashicorp.com/terraform/$(TERRAFORM_VERSION)/terraform_$(TERRAFORM_VERSION)_$(OS_LOWER)_$(ARCH).zip
TERRAFORM_DOCS_URL := https://github.com/terraform-docs/terraform-docs/releases/download/v$(TERRAFORM_DOCS_VERSION)/terraform-docs-v$(TERRAFORM_DOCS_VERSION)-$(OS_LOWER)-$(ARCH).tar.gz
TRIVY_URL := https://github.com/aquasecurity/trivy/releases/download/v$(TRIVY_VERSION)/trivy_$(TRIVY_VERSION)_$(OS)-64bit.tar.gz
TFLINT_URL := https://github.com/terraform-linters/tflint/releases/download/v$(TFLINT_VERSION)/tflint_$(OS_LOWER)_$(ARCH).zip
PACKER_URL := https://releases.hashicorp.com/packer/$(PACKER_VERSION)/packer_$(PACKER_VERSION)_$(OS_LOWER)_$(ARCH).zip
SOPS_URL := https://github.com/getsops/sops/releases/download/v$(SOPS_VERSION)/sops-v$(SOPS_VERSION).$(OS_LOWER).$(ARCH)

# check_and_upgrade <binary>,<version-flag>,<expected-version>,<install-target>
define check_and_upgrade
if [ ! -x "$(BIN_DIR)/$(1)" ]; then \
	echo "  ⬇️  $(1) not installed → installing $(3)..."; \
	$(MAKE) --no-print-directory $(4); \
else \
	INSTALLED=$$($(BIN_DIR)/$(1) $(2) 2>&1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -n1); \
	if [ "$$INSTALLED" != "$(3)" ]; then \
		echo "  🔄 $(1) $$INSTALLED → $(3), upgrading..."; \
		$(MAKE) --no-print-directory $(4); \
	else \
		echo "  ✅ $(1) $$INSTALLED (up to date)"; \
	fi; \
fi
endef

help: ## Show this help message
	@echo "Usage: make [target]"
	@echo ""
	@echo "System information:"
	@echo "  OS:              $(OS) ($(OS_LOWER))"
	@echo "  Architecture:    $(ARCH) ($(ARCH_ORIG))"
	@echo ""
	@echo "Targets:"
	@grep -E '^[a-zA-Z0-9_-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  %-20s %s\n", $$1, $$2}'

debug: ## Show detected system information and configured tool versions
	@echo "System Information:"
	@echo "  Detected OS:     $(OS)"
	@echo "  OS (lowercase):  $(OS_LOWER)"
	@echo "  Architecture:    $(ARCH)"
	@echo "  Arch (original): $(ARCH_ORIG)"
	@echo "  uname -s:        $(UNAME_S)"
	@echo "  uname -m:        $(UNAME_M)"
	@echo ""
	@echo "Tool Versions (configured):"
	@echo "  Terraform:       $(TERRAFORM_VERSION)"
	@echo "  Terraform-docs:  $(TERRAFORM_DOCS_VERSION)"
	@echo "  Trivy:           $(TRIVY_VERSION)"
	@echo "  TFLint:          $(TFLINT_VERSION)"
	@echo "  Packer:          $(PACKER_VERSION)"
	@echo "  SOPS:            $(SOPS_VERSION)"
	@echo ""
	@echo "Download URLs:"
	@echo "  Terraform:       $(TERRAFORM_URL)"
	@echo "  Terraform-docs:  $(TERRAFORM_DOCS_URL)"
	@echo "  Trivy:           $(TRIVY_URL)"
	@echo "  TFLint:          $(TFLINT_URL)"
	@echo "  Packer:          $(PACKER_URL)"
	@echo "  SOPS:            $(SOPS_URL)"
	@echo ""
	@echo "Directories:"
	@echo "  BIN_DIR:         $(BIN_DIR)"
	@echo ""
	@if [ -d "$(BIN_DIR)" ]; then \
		echo "Installed Tool Versions:"; \
		echo "  Terraform:       $$($(BIN_DIR)/terraform version 2>/dev/null | head -n1 || echo 'not installed')"; \
		echo "  Terraform-docs:  $$($(BIN_DIR)/terraform-docs version 2>/dev/null | head -n1 || echo 'not installed')"; \
		echo "  Trivy:           $$($(BIN_DIR)/trivy --version 2>/dev/null | head -n1 || echo 'not installed')"; \
		echo "  TFLint:          $$($(BIN_DIR)/tflint --version 2>/dev/null || echo 'not installed')"; \
		echo "  Packer:          $$($(BIN_DIR)/packer version 2>/dev/null || echo 'not installed')"; \
		echo "  SOPS:            $$($(BIN_DIR)/sops --version --disable-version-check 2>/dev/null || echo 'not installed')"; \
	else \
		echo "No tools installed yet. Run 'make install' to install them."; \
	fi

check: ## Check installed binaries and upgrade any that are missing or out of date
	@echo "🔍 Checking binaries in $(BIN_DIR)..."
	@mkdir -p $(BIN_DIR)
	@$(call check_and_upgrade,terraform,version,$(TERRAFORM_VERSION),install-terraform)
	@$(call check_and_upgrade,terraform-docs,version,$(TERRAFORM_DOCS_VERSION),install-terraform-docs)
	@$(call check_and_upgrade,trivy,--version,$(TRIVY_VERSION),install-trivy)
	@$(call check_and_upgrade,tflint,--version,$(TFLINT_VERSION),install-tflint)
	@$(call check_and_upgrade,packer,version,$(PACKER_VERSION),install-packer)
	@$(call check_and_upgrade,sops,--version --disable-version-check,$(SOPS_VERSION),install-sops)
	@echo "✅ Check complete"

install: check direnv-allow pre-commit-install ansible-deps ## Prepare everything a contributor needs: pinned binaries, direnv approval, pre-commit hooks, Ansible virtualenv + collections

install-binaries: install-terraform install-terraform-docs install-trivy install-tflint install-packer install-sops ## Force-reinstall all binaries regardless of current version
	@echo "✅ Binaries installed successfully"

install-terraform:
	@echo "  → Installing Terraform $(TERRAFORM_VERSION)..."
	@mkdir -p $(BIN_DIR)
	@curl -fsSL $(TERRAFORM_URL) -o /tmp/terraform.zip
	@unzip -oq /tmp/terraform.zip terraform -d $(BIN_DIR)
	@chmod +x $(BIN_DIR)/terraform
	@rm /tmp/terraform.zip

install-terraform-docs:
	@echo "  → Installing Terraform-docs $(TERRAFORM_DOCS_VERSION)..."
	@mkdir -p $(BIN_DIR)
	@curl -fsSL $(TERRAFORM_DOCS_URL) -o /tmp/terraform-docs.tar.gz
	@tar -xzf /tmp/terraform-docs.tar.gz -C /tmp terraform-docs
	@mv /tmp/terraform-docs $(BIN_DIR)/terraform-docs
	@chmod +x $(BIN_DIR)/terraform-docs
	@rm /tmp/terraform-docs.tar.gz

install-trivy:
	@echo "  → Installing Trivy $(TRIVY_VERSION)..."
	@mkdir -p $(BIN_DIR)
	@curl -fsSL $(TRIVY_URL) -o /tmp/trivy.tar.gz
	@tar -xzf /tmp/trivy.tar.gz -C /tmp trivy
	@mv /tmp/trivy $(BIN_DIR)/trivy
	@chmod +x $(BIN_DIR)/trivy
	@rm /tmp/trivy.tar.gz

install-tflint:
	@echo "  → Installing TFLint $(TFLINT_VERSION)..."
	@mkdir -p $(BIN_DIR)
	@curl -fsSL $(TFLINT_URL) -o /tmp/tflint.zip
	@unzip -oq /tmp/tflint.zip -d $(BIN_DIR)
	@chmod +x $(BIN_DIR)/tflint
	@rm /tmp/tflint.zip
	@echo "  → Initializing TFLint rulesets..."
	@$(BIN_DIR)/tflint --init

install-packer:
	@echo "  → Installing Packer $(PACKER_VERSION)..."
	@mkdir -p $(BIN_DIR)
	@curl -fsSL $(PACKER_URL) -o /tmp/packer.zip
	@unzip -oq /tmp/packer.zip packer -d $(BIN_DIR)
	@chmod +x $(BIN_DIR)/packer
	@rm /tmp/packer.zip

install-sops:
	@echo "  → Installing SOPS $(SOPS_VERSION)..."
	@mkdir -p $(BIN_DIR)
	@curl -fsSL $(SOPS_URL) -o $(BIN_DIR)/sops
	@chmod +x $(BIN_DIR)/sops

clean: ## Remove temporary installation files
	@echo "🧹 Cleaning temporary files..."
	@rm -rf /tmp/terraform.zip /tmp/terraform-docs.tar.gz /tmp/trivy.tar.gz /tmp/tflint.zip /tmp/packer.zip
	@echo "✅ Cleanup complete"

direnv-allow: ## Approve .envrc files at repo root and in packer/, terraform/, ansible/
	@command -v direnv >/dev/null 2>&1 || { echo "❌ direnv not installed"; exit 1; }
	@command -v age >/dev/null 2>&1 || { echo "❌ age not installed"; exit 1; }
	direnv allow .
	direnv allow packer
	direnv allow terraform
	direnv allow ansible

pre-commit-install: ## Install git hooks via pre-commit (commit + commit-msg stages)
	@command -v pre-commit >/dev/null 2>&1 || { echo "❌ pre-commit not installed"; exit 1; }
	pre-commit install
	pre-commit install --hook-type commit-msg

# --------------------------------------------------------------------------
# Packer -> Terraform -> Ansible pipeline
#
# Only non-mutating setup lives here. The actual writes (packer build,
# terraform apply, ansible-playbook) are deliberately NOT Makefile targets —
# run them directly, by hand, from their own directory (see each tool's
# README). That keeps the write path a single explicit command, not a
# wrapper someone can invoke without thinking, and it's the same command
# GitHub Actions will run later.
# --------------------------------------------------------------------------

packer-init: ## Initialize Packer plugins for the Ubuntu 26.04 template
	cd $(PACKER_DIR) && packer init .

tf-init: ## Initialize Terraform (HCP Terraform backend + providers)
	cd $(TERRAFORM_DIR) && terraform init

venv: ## Create the local Python virtualenv (.venv) used to run Ansible
	@command -v python3 >/dev/null 2>&1 || { echo "❌ python3 not installed"; exit 1; }
	@if [ ! -d "$(VENV_DIR)" ]; then \
		echo "🐍 Creating virtualenv at $(VENV_DIR)..."; \
		python3 -m venv $(VENV_DIR); \
	fi

ansible-install: venv ## Install Ansible into the virtualenv (pip install -r requirements.txt)
	@$(VENV_DIR)/bin/pip install --upgrade pip >/dev/null
	@$(VENV_DIR)/bin/pip install -r requirements.txt
	@echo "✅ Ansible installed in $(VENV_DIR)"

ansible-deps: ansible-install ## Install required Ansible collections (into the virtualenv)
	cd $(ANSIBLE_DIR) && $(VENV_DIR)/bin/ansible-galaxy collection install -r requirements.yml
