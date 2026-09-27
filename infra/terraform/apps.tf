# The four container apps. Created only when deploy_apps = true (images must be
# in ACR first — see DEPLOY.md).
#
# All four are internal-only. The ONLY public entry point is the route config at
# the bottom of this file: one origin serving the webapp at / and the APIs at
# /api/<resource>/*. Same origin means no CORS in Azure, and the webapp image
# calls relative /api paths — nothing environment-specific is baked into it.

locals {
  # Names come from the naming convention in main.tf.
  candidate_app_name   = local.app_names.candidate
  job_app_name         = local.app_names.job
  application_app_name = local.app_names.application
  webapp_app_name      = local.app_names.webapp
  route_config_name    = local.names.route_config

  registry = azurerm_container_registry.main.login_server

  # Reachable only inside the environment (and, for the API apps, used by
  # ApplicationService for its sync existence checks).
  candidate_internal_url   = "https://${local.candidate_app_name}.internal.${azurerm_container_app_environment.main.default_domain}"
  job_internal_url         = "https://${local.job_app_name}.internal.${azurerm_container_app_environment.main.default_domain}"
  application_internal_url = "https://${local.application_app_name}.internal.${azurerm_container_app_environment.main.default_domain}"

  # The route config's default FQDN always works; the custom domain, if set,
  # is the same entry point under your own name.
  route_url = "https://${local.route_config_name}.${azurerm_container_app_environment.main.default_domain}"
  site_url  = var.webapp_custom_domain != "" ? "https://${var.webapp_custom_domain}" : local.route_url
}

resource "azurerm_container_app" "candidate" {
  count = var.deploy_apps ? 1 : 0

  name                         = local.candidate_app_name
  container_app_environment_id = azurerm_container_app_environment.main.id
  resource_group_name          = azurerm_resource_group.main.name
  revision_mode                = "Single"
  workload_profile_name        = "Consumption" # the env's serverless profile (main.tf)
  tags                         = local.tags

  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.apps.id]
  }

  registry {
    server   = local.registry
    identity = azurerm_user_assigned_identity.apps.id
  }

  secret {
    name  = "cosmos-key"
    value = azurerm_cosmosdb_account.main.primary_key
  }

  ingress {
    # Internal-only: reachable inside the environment and via the route config,
    # not on a public FQDN of its own.
    external_enabled = false
    target_port      = 8080
    traffic_weight {
      latest_revision = true
      percentage      = 100
    }
  }

  template {
    min_replicas = var.min_replicas
    max_replicas = 1

    container {
      name   = "candidate-service"
      image  = "${local.registry}/candidate-service:${var.image_tag}"
      cpu    = 0.25
      memory = "0.5Gi"

      env {
        name  = "Cosmos__Endpoint"
        value = azurerm_cosmosdb_account.main.endpoint
      }
      env {
        name        = "Cosmos__Key"
        secret_name = "cosmos-key"
      }
    }
  }

  # The per-service CI/CD pipelines roll out new images with
  # `az containerapp update`; Terraform must not revert them on the next apply.
  # Split of ownership: Terraform owns the app's shape, pipelines own the image.
  lifecycle {
    ignore_changes = [template[0].container[0].image]
  }

  depends_on = [azurerm_role_assignment.acr_pull]
}

resource "azurerm_container_app" "job" {
  count = var.deploy_apps ? 1 : 0

  name                         = local.job_app_name
  container_app_environment_id = azurerm_container_app_environment.main.id
  resource_group_name          = azurerm_resource_group.main.name
  revision_mode                = "Single"
  workload_profile_name        = "Consumption" # the env's serverless profile (main.tf)
  tags                         = local.tags

  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.apps.id]
  }

  registry {
    server   = local.registry
    identity = azurerm_user_assigned_identity.apps.id
  }

  secret {
    name  = "cosmos-key"
    value = azurerm_cosmosdb_account.main.primary_key
  }

  ingress {
    # Internal-only: reachable inside the environment and via the route config,
    # not on a public FQDN of its own.
    external_enabled = false
    target_port      = 8080
    traffic_weight {
      latest_revision = true
      percentage      = 100
    }
  }

  template {
    min_replicas = var.min_replicas
    max_replicas = 1

    container {
      name   = "job-service"
      image  = "${local.registry}/job-service:${var.image_tag}"
      cpu    = 0.25
      memory = "0.5Gi"

      env {
        name  = "Cosmos__Endpoint"
        value = azurerm_cosmosdb_account.main.endpoint
      }
      env {
        name        = "Cosmos__Key"
        secret_name = "cosmos-key"
      }
    }
  }

  # The per-service CI/CD pipelines roll out new images with
  # `az containerapp update`; Terraform must not revert them on the next apply.
  # Split of ownership: Terraform owns the app's shape, pipelines own the image.
  lifecycle {
    ignore_changes = [template[0].container[0].image]
  }

  depends_on = [azurerm_role_assignment.acr_pull]
}

resource "azurerm_container_app" "application" {
  count = var.deploy_apps ? 1 : 0

  name                         = local.application_app_name
  container_app_environment_id = azurerm_container_app_environment.main.id
  resource_group_name          = azurerm_resource_group.main.name
  revision_mode                = "Single"
  workload_profile_name        = "Consumption" # the env's serverless profile (main.tf)
  tags                         = local.tags

  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.apps.id]
  }

  registry {
    server   = local.registry
    identity = azurerm_user_assigned_identity.apps.id
  }

  secret {
    name  = "cosmos-key"
    value = azurerm_cosmosdb_account.main.primary_key
  }

  ingress {
    # Internal-only: reachable inside the environment and via the route config,
    # not on a public FQDN of its own.
    external_enabled = false
    target_port      = 8080
    traffic_weight {
      latest_revision = true
      percentage      = 100
    }
  }

  template {
    min_replicas = var.min_replicas
    max_replicas = 1

    container {
      name   = "application-service"
      image  = "${local.registry}/application-service:${var.image_tag}"
      cpu    = 0.25
      memory = "0.5Gi"

      env {
        name  = "Cosmos__Endpoint"
        value = azurerm_cosmosdb_account.main.endpoint
      }
      env {
        name        = "Cosmos__Key"
        secret_name = "cosmos-key"
      }
      # Sync existence checks stay inside the environment (internal FQDNs).
      env {
        name  = "Services__CandidateApi"
        value = local.candidate_internal_url
      }
      env {
        name  = "Services__JobApi"
        value = local.job_internal_url
      }
    }
  }

  # The per-service CI/CD pipelines roll out new images with
  # `az containerapp update`; Terraform must not revert them on the next apply.
  # Split of ownership: Terraform owns the app's shape, pipelines own the image.
  lifecycle {
    ignore_changes = [template[0].container[0].image]
  }

  depends_on = [azurerm_role_assignment.acr_pull]
}

# The route config was API-only when it was named api_routes; it now fronts the
# whole site. `moved` renames it in state instead of destroying and recreating it.
moved {
  from = azapi_resource.api_routes
  to   = azapi_resource.routes
}

# Rule-based routing (PREVIEW): the single public entry point of the environment,
# the platform's replacement for a self-hosted gateway. azurerm has no resource
# for this yet, hence azapi. Rules are matched IN ORDER: the /api prefixes first,
# the "/" catch-all for the webapp last — otherwise it would swallow /api too.
resource "azapi_resource" "routes" {
  count = var.deploy_apps ? 1 : 0

  type      = "Microsoft.App/managedEnvironments/httpRouteConfigs@2025-10-02-preview"
  name      = local.route_config_name
  parent_id = azurerm_container_app_environment.main.id

  body = {
    properties = {
      # A domain binds to exactly ONE of: an app, a route config, or the
      # environment — so it must not also be on the webapp. "Auto" attaches the
      # environment's existing managed certificate for this hostname, which is
      # created once outside Terraform (see DEPLOY.md, custom domain).
      customDomains = var.webapp_custom_domain == "" ? [] : [
        {
          name        = var.webapp_custom_domain
          bindingType = "Auto"
        }
      ]
      rules = [
        {
          description = "Candidate service"
          routes = [
            {
              match  = { prefix = "/api/candidates" }
              action = { prefixRewrite = "/candidates" }
            }
          ]
          targets = [{ containerApp = local.candidate_app_name }]
        },
        {
          description = "Job service"
          routes = [
            {
              match  = { prefix = "/api/jobs" }
              action = { prefixRewrite = "/jobs" }
            }
          ]
          targets = [{ containerApp = local.job_app_name }]
        },
        {
          description = "Application service"
          routes = [
            {
              match  = { prefix = "/api/applications" }
              action = { prefixRewrite = "/applications" }
            }
          ]
          targets = [{ containerApp = local.application_app_name }]
        },
        {
          # Catch-all: everything else is the SPA (nginx falls back to index.html).
          description = "Webapp"
          routes = [
            {
              match = { prefix = "/" }
            }
          ]
          targets = [{ containerApp = local.webapp_app_name }]
        }
      ]
    }
  }

  depends_on = [
    azurerm_container_app.candidate,
    azurerm_container_app.job,
    azurerm_container_app.application,
    azurerm_container_app.webapp,
  ]
}

resource "azurerm_container_app" "webapp" {
  count = var.deploy_apps ? 1 : 0

  name                         = local.webapp_app_name
  container_app_environment_id = azurerm_container_app_environment.main.id
  resource_group_name          = azurerm_resource_group.main.name
  revision_mode                = "Single"
  workload_profile_name        = "Consumption" # the env's serverless profile (main.tf)
  tags                         = local.tags

  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.apps.id]
  }

  registry {
    server   = local.registry
    identity = azurerm_user_assigned_identity.apps.id
  }

  ingress {
    # Internal-only like the APIs: served to the internet solely through the
    # route config's "/" rule.
    external_enabled = false
    target_port      = 80
    traffic_weight {
      latest_revision = true
      percentage      = 100
    }
  }

  template {
    min_replicas = var.min_replicas
    max_replicas = 1

    container {
      name   = "webapp"
      image  = "${local.registry}/webapp:${var.image_tag}"
      cpu    = 0.25
      memory = "0.5Gi"
      # No env vars: the bundle calls relative /api paths on its own origin.
    }
  }

  # The per-service CI/CD pipelines roll out new images with
  # `az containerapp update`; Terraform must not revert them on the next apply.
  # Split of ownership: Terraform owns the app's shape, pipelines own the image.
  lifecycle {
    ignore_changes = [template[0].container[0].image]
  }

  depends_on = [azurerm_role_assignment.acr_pull]
}
