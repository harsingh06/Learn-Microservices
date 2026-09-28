terraform {
  required_version = ">= 1.9"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
  }

  # Same storage account as the platform, own state file: this stack can only
  # ever plan changes to this service's own resources.
  backend "azurerm" {
    resource_group_name  = "ats-tfstate-rg"
    storage_account_name = "atstfstate4sqlo"
    container_name       = "tfstate"
    key                  = "svc-webapp.tfstate"
  }
}

provider "azurerm" {
  features {}
  subscription_id = var.subscription_id
}
