.PHONY: help init validate build debug clean format inspect gen-example-vars check-vars

# Default target
.DEFAULT_GOAL := help

# Variables
VAR_FILE := variables.pkrvars.hcl
EXAMPLE_VAR_FILE := variables.pkrvars.hcl.example
VAR_DEF_FILE := variables.pkr.hcl
PACKER_TEMPLATE := .

# Colors for output
GREEN := \033[0;32m
YELLOW := \033[0;33m
RED := \033[0;31m
NC := \033[0m # No Color

help: ## Show this help message
	@echo "$(GREEN)Packer Template Automation$(NC)"
	@echo ""
	@echo "Usage: make [target]"
	@echo ""
	@echo "Available targets:"
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "  $(GREEN)%-15s$(NC) %s\n", $$1, $$2}'

init: ## Initialize Packer (install plugins)
	@echo "$(GREEN)Initializing Packer...$(NC)"
	packer init $(PACKER_TEMPLATE)

validate: check-vars ## Validate Packer template
	@echo "$(GREEN)Validating Packer template...$(NC)"
	packer validate -var-file="$(VAR_FILE)" $(PACKER_TEMPLATE)
	@echo "$(GREEN)✓ Validation successful$(NC)"

build: check-vars validate ## Build the image
	@echo "$(GREEN)Building image...$(NC)"
	packer build -var-file="$(VAR_FILE)" $(PACKER_TEMPLATE)
	@echo "$(GREEN)✓ Build complete$(NC)"

debug: check-vars ## Build with debug output
	@echo "$(YELLOW)Building with debug output...$(NC)"
	PACKER_LOG=1 packer build -debug -var-file="$(VAR_FILE)" $(PACKER_TEMPLATE)

force-build: check-vars ## Force build (skip validation)
	@echo "$(YELLOW)Force building (skipping validation)...$(NC)"
	packer build -force -var-file="$(VAR_FILE)" $(PACKER_TEMPLATE)

clean: ## Remove build artifacts and cache
	@echo "$(YELLOW)Cleaning build artifacts...$(NC)"
	rm -rf output-*
	rm -rf packer_cache
	rm -rf crash.log
	@echo "$(GREEN)✓ Cleanup complete$(NC)"

format: ## Format all HCL files
	@echo "$(GREEN)Formatting HCL files...$(NC)"
	packer fmt -recursive .
	@echo "$(GREEN)✓ Formatting complete$(NC)"

inspect: ## Show detailed template information
	@echo "$(GREEN)Inspecting template...$(NC)"
	packer inspect $(PACKER_TEMPLATE)

gen-example-vars: ## Generate variables.pkrvars.hcl.example from variables.pkr.hcl
	@echo "$(GREEN)Generating example variables file...$(NC)"
	@if [ -f "$(VAR_DEF_FILE)" ]; then \
		python3 tools/generate_example_vars.py; \
		echo "$(GREEN)✓ Generated $(EXAMPLE_VAR_FILE)$(NC)"; \
	else \
		echo "$(RED)✗ $(VAR_DEF_FILE) not found$(NC)"; \
		exit 1; \
	fi

docs: ## Update README.md with variable documentation (table format)
	@echo "$(GREEN)Updating README.md with variable documentation...$(NC)"
	python3 tools/generate_vars_docs.py --mode table
	@echo "$(GREEN)✓ Documentation updated$(NC)"

docs-detailed: ## Update README.md with detailed variable documentation
	@echo "$(GREEN)Updating README.md with detailed variable documentation...$(NC)"
	python3 tools/generate_vars_docs.py --mode detailed
	@echo "$(GREEN)✓ Detailed documentation updated$(NC)"

docs-preview: ## Preview variable documentation without updating README
	@echo "$(GREEN)Variable Documentation Preview:$(NC)"
	@echo ""
	@python3 generate_vars_docs.py --output stdout --mode table

docs-all: example-vars docs ## Generate example vars and update all documentation
	@echo "$(GREEN)✓ All documentation updated$(NC)"

check-vars: ## Check if variables file exists
	@if [ ! -f "$(VAR_FILE)" ]; then \
		echo "$(RED)✗ $(VAR_FILE) not found!$(NC)"; \
		echo "$(YELLOW)  Create it from the example:$(NC)"; \
		echo "  cp $(EXAMPLE_VAR_FILE) $(VAR_FILE)"; \
		exit 1; \
	fi

install-deps: ## Install required Python dependencies
	@echo "$(GREEN)Installing Python dependencies...$(NC)"
	pip3 install python-hcl2
	@echo "$(GREEN)✓ Dependencies installed$(NC)"

setup: install-deps example-vars docs-all ## Complete project setup with documentation
	@echo "$(GREEN)Setting up project...$(NC)"
	@if [ ! -f "$(VAR_FILE)" ]; then \
		cp $(EXAMPLE_VAR_FILE) $(VAR_FILE); \
		echo "$(GREEN)✓ Created $(VAR_FILE) from example$(NC)"; \
		echo "$(YELLOW)⚠ Please edit $(VAR_FILE) with your values$(NC)"; \
	fi
	@$(MAKE) init
	@echo "$(GREEN)✓ Setup complete$(NC)"

version: ## Show Packer version
	@packer version

.gitignore: ## Generate .gitignore file
	@echo "$(GREEN)Generating .gitignore...$(NC)"
	@echo "# Packer" > .gitignore
	@echo "packer_cache/" >> .gitignore
	@echo "crash.log" >> .gitignore
	@echo "output-*/" >> .gitignore
	@echo "" >> .gitignore
	@echo "# Variables" >> .gitignore
	@echo "variables.pkrvars.hcl" >> .gitignore
	@echo "*.auto.pkrvars.hcl" >> .gitignore
	@echo "" >> .gitignore
	@echo "# OS" >> .gitignore
	@echo ".DS_Store" >> .gitignore
	@echo "Thumbs.db" >> .gitignore
	@echo "" >> .gitignore
	@echo "# IDE" >> .gitignore
	@echo ".vscode/" >> .gitignore
	@echo ".idea/" >> .gitignore
	@echo "*.swp" >> .gitignore
	@echo "*.swo" >> .gitignore
	@echo "$(GREEN)✓ .gitignore created$(NC)"
