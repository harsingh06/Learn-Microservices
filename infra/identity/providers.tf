# Entra ID (Azure AD) configuration for ATS sign-in: app registrations, scopes,
# app roles, role assignments and test users. See AUTH.md.
#
# Applied by YOU, locally, signed in as a tenant administrator (az login) — not by
# CI: managing app registrations needs Microsoft Graph permissions that the
# pipeline identity deliberately doesn't have.
terraform {
  required_version = ">= 1.9"

  required_providers {
    azuread = {
      source  = "hashicorp/azuread"
      version = "~> 3.10"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }

  # Same storage account as the platform stack, separate state file.
  backend "azurerm" {
    resource_group_name  = "ats-tfstate-rg"
    storage_account_name = "atstfstate4sqlo"
    container_name       = "tfstate"
    key                  = "identity.tfstate"
  }
}

provider "azuread" {
  tenant_id = var.tenant_id
}
