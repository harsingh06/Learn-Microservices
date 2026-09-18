# The four container apps. Created only when deploy_apps = true (images must be
# in ACR first — see DEPLOY.md).
#
# App URLs are deterministic once the environment exists:
#   https://<app-name>.<environment default_domain>
# which is why the URLs below can be computed (and output, and baked into the
# webapp image) BEFORE the apps themselves are created.

locals {
  candidate_app_name   = "${var.prefix}-candidate"
  job_app_name         = "${var.prefix}-job"
  application_app_name = "${var.prefix}-application"
  webapp_app_name      = "${var.prefix}-webapp"
  # Route config names must match ^[a-z][a-z0-9]*$ (no hyphens).
  route_config_name = "${var.prefix}routes"

  registry = azurerm_container_registry.main.login_server

  # The API apps are internal-only: reachable inside the environment on their
  # *.internal.* FQDNs, and from the internet ONLY via the route config below.
  candidate_internal_url   = "https://${local.candidate_app_name}.internal.${azurerm_container_app_environment.main.default_domain}"
  job_internal_url         = "https://${local.job_app_name}.internal.${azurerm_container_app_environment.main.default_domain}"
  application_internal_url = "https://${local.application_app_name}.internal.${azurerm_container_app_environment.main.default_domain}"

  # Public API entry point (environment-level rule-based routing FQDN).
  api_url    = "https://${local.route_config_name}.${azurerm_container_app_environment.main.default_domain}"
  webapp_url = "https://${local.webapp_app_name}.${azurerm_container_app_environment.main.default_domain}"
}

resource "azurerm_container_app" "candidate" {
  count = var.deploy_apps ? 1 : 0

  name                         = local.candidate_app_name
  container_app_environment_id = azurerm_container_app_environment.main.id
  resource_group_name          = azurerm_resource_group.main.name
  revision_mode                = "Single"

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

# Custom domain for the webapp. The hostname is managed here, but the FREE
# managed TLS certificate cannot be created by the azurerm provider — it is
# provisioned once via `az containerapp hostname bind` (see DEPLOY.md), and the
# lifecycle block stops Terraform from stripping that binding on later applies.
resource "azurerm_container_app_custom_domain" "webapp" {
  count = var.deploy_apps && var.webapp_custom_domain != "" ? 1 : 0

  name             = var.webapp_custom_domain
  container_app_id = azurerm_container_app.webapp[0].id

  lifecycle {
    ignore_changes = [certificate_binding_type, container_app_environment_certificate_id]
  }
}

# Rule-based routing (PREVIEW): one environment-level FQDN routes /api/<resource>/*
# to the owning internal-only app — the platform's replacement for a self-hosted
# gateway. azurerm has no resource for this yet, hence azapi. Rule order matters:
# more specific prefixes must come first (ours don't overlap).
resource "azapi_resource" "api_routes" {
  count = var.deploy_apps ? 1 : 0

  type      = "Microsoft.App/managedEnvironments/httpRouteConfigs@2025-10-02-preview"
  name      = local.route_config_name
  parent_id = azurerm_container_app_environment.main.id

  body = {
    properties = {
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
        }
      ]
    }
  }

  depends_on = [
    azurerm_container_app.candidate,
    azurerm_container_app.job,
    azurerm_container_app.application,
  ]
}

resource "azurerm_container_app" "webapp" {
  count = var.deploy_apps ? 1 : 0

  name                         = local.webapp_app_name
  container_app_environment_id = azurerm_container_app_environment.main.id
  resource_group_name          = azurerm_resource_group.main.name
  revision_mode                = "Single"

  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.apps.id]
  }

  registry {
    server   = local.registry
    identity = azurerm_user_assigned_identity.apps.id
  }

  ingress {
    external_enabled = true
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
      # No env vars: the API URLs were baked in at image build time (see DEPLOY.md).
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
