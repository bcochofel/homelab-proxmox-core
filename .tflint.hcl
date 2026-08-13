# TFLint configuration for Terraform linting
# See https://github.com/terraform-linters/tflint/blob/master/docs/user-guide/config.md

config {
  # Call module type - options: all, local, none
  # "all" inspects all modules including remote modules
  # "local" inspects only local modules
  # "none" disables module inspection
  call_module_type = "all"

  # Force checking even if there are errors
  force = false

  # Plugin cache directory
  plugin_dir = "~/.tflint.d/plugins"

  # Disable colored output in CI
  # color = false
}

# Terraform plugin (built-in)
plugin "terraform" {
  enabled = true
  preset  = "recommended"

  # Custom rules
  version = "0.15.0"
  source  = "github.com/terraform-linters/tflint-ruleset-terraform"
}

# VMware vSphere specific rules
# Note: There is no official tflint-ruleset-vsphere yet
# Using terraform plugin rules which apply to all providers

# AWS Plugin (disabled - not using AWS)
plugin "aws" {
  enabled = false
  version = "0.48.0"
  source  = "github.com/terraform-linters/tflint-ruleset-aws"
}

# Azure Plugin (disabled - not using Azure)
plugin "azurerm" {
  enabled = false
  version = "0.32.0"
  source  = "github.com/terraform-linters/tflint-ruleset-azurerm"
}

# Google Cloud Plugin (disabled - not using GCP)
plugin "google" {
  enabled = false
  version = "0.39.0"
  source  = "github.com/terraform-linters/tflint-ruleset-google"
}

# Rule configurations
rule "terraform_deprecated_interpolation" {
  enabled = true
}

rule "terraform_deprecated_index" {
  enabled = true
}

rule "terraform_unused_declarations" {
  enabled = true
}

rule "terraform_comment_syntax" {
  enabled = true
}

rule "terraform_documented_outputs" {
  enabled = true
}

rule "terraform_documented_variables" {
  enabled = true
}

rule "terraform_typed_variables" {
  enabled = true
}

rule "terraform_module_pinned_source" {
  enabled = true
  style = "semver"
}

rule "terraform_naming_convention" {
  enabled = true

  # Variable naming
  variable {
    format = "snake_case"
  }

  # Local naming
  locals {
    format = "snake_case"
  }

  # Output naming
  output {
    format = "snake_case"
  }

  # Resource naming
  resource {
    format = "snake_case"
  }

  # Module naming
  module {
    format = "snake_case"
  }

  # Data source naming
  data {
    format = "snake_case"
  }
}

rule "terraform_required_version" {
  enabled = true
}

rule "terraform_required_providers" {
  enabled = true
}

rule "terraform_standard_module_structure" {
  enabled = true
}

rule "terraform_workspace_remote" {
  enabled = true
}

# Disable rules that might be too strict
rule "terraform_unused_required_providers" {
  enabled = false
}
