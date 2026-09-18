terraform {
  required_version = ">= 1.9"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }

  # Remote state so both your laptop and the GitHub Actions infra pipeline
  # work against the same state. The storage account is the one piece of
  # infrastructure created OUTSIDE Terraform (bootstrap chicken-and-egg).
  backend "azurerm" {
    resource_group_name  = "ats-tfstate-rg"
    storage_account_name = "atstfstate4sqlo"
    container_name       = "tfstate"
    key                  = "ats.tfstate"
  }
}

provider "azurerm" {
  features {}

  # azurerm v4 requires the subscription explicitly (no longer inferred from az cli).
  subscription_id = var.subscription_id
}
