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
  gateway_app_name     = "${var.prefix}-gateway"
  webapp_app_name      = "${var.prefix}-webapp"

  registry = azurerm_container_registry.main.login_server

  candidate_api_url   = "https://${local.candidate_app_name}.${azurerm_container_app_environment.main.default_domain}"
  job_api_url         = "https://${local.job_app_name}.${azurerm_container_app_environment.main.default_domain}"
  application_api_url = "https://${local.application_app_name}.${azurerm_container_app_environment.main.default_domain}"
  gateway_url         = "https://${local.gateway_app_name}.${azurerm_container_app_environment.main.default_domain}"
  webapp_url          = "https://${local.webapp_app_name}.${azurerm_container_app_environment.main.default_domain}"
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
    external_enabled = true
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
    external_enabled = true
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
    external_enabled = true
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
      # Sync existence checks go to the other apps' public URLs.
      env {
        name  = "Services__CandidateApi"
        value = local.candidate_api_url
      }
      env {
        name  = "Services__JobApi"
        value = local.job_api_url
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

resource "azurerm_container_app" "gateway" {
  count = var.deploy_apps ? 1 : 0

  name                         = local.gateway_app_name
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
      name   = "api-gateway"
      image  = "${local.registry}/api-gateway:${var.image_tag}"
      cpu    = 0.25
      memory = "0.5Gi"

      # YARP cluster destinations (public service URLs for now; internal-only
      # ingress for the APIs is a backlog item).
      env {
        name  = "ReverseProxy__Clusters__candidates__Destinations__primary__Address"
        value = local.candidate_api_url
      }
      env {
        name  = "ReverseProxy__Clusters__jobs__Destinations__primary__Address"
        value = local.job_api_url
      }
      env {
        name  = "ReverseProxy__Clusters__applications__Destinations__primary__Address"
        value = local.application_api_url
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
