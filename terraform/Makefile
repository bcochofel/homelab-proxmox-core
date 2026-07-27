.PHONY: help init validate build

# Default target
.DEFAULT_GOAL := help

# Variables
TF_ROOT := .

# Colors for output
GREEN := \033[0;32m
YELLOW := \033[0;33m
RED := \033[0;31m
NC := \033[0m # No Color

help: ## Show this help message
	@echo "$(GREEN)Terraform Automation$(NC)"
	@echo ""
	@echo "Usage: make [target]"
	@echo ""
	@echo "Available targets:"
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "  $(GREEN)%-15s$(NC) %s\n", $$1, $$2}'

init: ## terraform init
	@echo "$(GREEN)Terraform Init...$(NC)"
	terraform init

validate: init ## terraform validate
	@echo "$(GREEN)Terraform Validate...$(NC)"
	terraform validate
	@echo "$(GREEN)✓ Validation successful$(NC)"

plan: validate ## terraform plan
	@echo "$(GREEN)Terraform Plan...$(NC)"
	terraform plan
	@echo "$(GREEN)✓ Plan complete$(NC)"

apply: validate ## terraform apply
	@echo "$(GREEN)Terraform Apply...$(NC)"
	terraform apply -auto-approve
	@echo "$(GREEN)✓ Apply complete$(NC)"
