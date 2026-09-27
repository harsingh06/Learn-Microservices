# Core infrastructure: resource group, logs, registry, identity, ACA environment.

# Naming convention: <type>-<workload>-<environment>-<region>-<instance>, with
# type abbreviations from Microsoft's Cloud Adoption Framework. Every resource
# name is built here, so the convention lives in exactly one place.
locals {
  # Add a region here before deploying to it (a missing key fails the plan).
  region_codes = {
    centralindia = "cin"
    southindia   = "sin"
    westindia    = "win"
  }
  region = local.region_codes[var.location]

  suffix = "${var.workload}-${var.environment}-${local.region}-${var.instance}" # ats-prod-cin-01
  flat   = replace(local.suffix, "-", "")                                       # atsprodcin01

  names = {
    resource_group = "rg-${local.suffix}"
    log_analytics  = "log-${local.suffix}"
    registry       = "acr${local.flat}" # alphanumeric only, globally unique
    identity_apps  = "id-${var.workload}-apps-${var.environment}-${local.region}-${var.instance}"
    environment    = "cae-${local.suffix}"
    cosmos         = "cosmos-${local.suffix}" # globally unique
    route_config   = "rt${local.flat}"        # ^[a-z][a-z0-9]*$, no hyphens
  }

  # Container app names, max 32 characters: ca-<workload>-<component>-<env>-<region>-<nn>.
  app_names = {
    for component in ["candidate", "job", "application", "webapp"] :
    component => "ca-${var.workload}-${component}-${var.environment}-${local.region}-${var.instance}"
  }

  tags = {
    workload    = var.workload
    environment = var.environment
    managed-by  = "terraform"
  }
}

resource "azurerm_resource_group" "main" {
  name     = local.names.resource_group
  location = var.location
  tags     = local.tags
}

# Container Apps stream console/system logs here (queryable in the portal).
resource "azurerm_log_analytics_workspace" "main" {
  name                = local.names.log_analytics
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  sku                 = "PerGB2018"
  retention_in_days   = 30
  tags                = local.tags
}

resource "azurerm_container_registry" "main" {
  name                = local.names.registry
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  sku                 = "Basic"
  # No admin user: the apps pull via managed identity (production pattern).
  admin_enabled = false
  tags          = local.tags
}

# One user-assigned identity shared by all container apps, allowed to pull from ACR.
resource "azurerm_user_assigned_identity" "apps" {
  name                = local.names.identity_apps
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  tags                = local.tags
}

resource "azurerm_role_assignment" "acr_pull" {
  scope                = azurerm_container_registry.main.id
  role_definition_name = "AcrPull"
  principal_id         = azurerm_user_assigned_identity.apps.principal_id
}

# No VNet: the environment uses Azure-managed networking. Ingress is public, but
# only the route config is external — every app is internal-only (apps.tf).
resource "azurerm_container_app_environment" "main" {
  name                       = local.names.environment
  location                   = azurerm_resource_group.main.location
  resource_group_name        = azurerm_resource_group.main.name
  log_analytics_workspace_id = azurerm_log_analytics_workspace.main.id
  tags                       = local.tags

  # Explicit rather than implied: new environments are workload-profiles type,
  # and the built-in serverless "Consumption" profile keeps scale-to-zero billing.
  workload_profile {
    name                  = "Consumption"
    workload_profile_type = "Consumption"
  }
}
