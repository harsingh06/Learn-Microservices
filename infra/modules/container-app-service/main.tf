# The standard for one container app in the ATS platform. Compute only: data
# (Cosmos) and exposure (routing, Front Door) belong to the platform stack.

resource "azurerm_container_app" "this" {
  name                         = var.name
  container_app_environment_id = var.platform.environment_id
  resource_group_name          = var.platform.resource_group_name
  revision_mode                = "Single"
  workload_profile_name        = "Consumption" # the environment's serverless profile
  tags                         = var.platform.tags

  # The shared apps identity: pulls from ACR (AcrPull granted by the platform).
  identity {
    type         = "UserAssigned"
    identity_ids = [var.platform.identity_id]
  }

  registry {
    server   = var.platform.registry_server
    identity = var.platform.identity_id
  }

  # Iterate the NAMES (not sensitive) so the values can stay sensitive.
  dynamic "secret" {
    for_each = nonsensitive(toset(keys(var.secrets)))
    content {
      name  = secret.value
      value = var.secrets[secret.value]
    }
  }

  # Always internal-only: the internet reaches apps solely through the platform's
  # route config (and Front Door in front of it).
  ingress {
    external_enabled = false
    target_port      = var.target_port
    traffic_weight {
      latest_revision = true
      percentage      = 100
    }
  }

  template {
    min_replicas = var.min_replicas
    max_replicas = var.max_replicas

    container {
      name   = var.container_name
      image  = var.image
      cpu    = var.cpu
      memory = var.memory

      dynamic "env" {
        for_each = var.env
        content {
          name        = env.key
          value       = env.value.value
          secret_name = env.value.secret
        }
      }
    }
  }

  # No ignore_changes on the image: the service pipeline passes the image into
  # this stack, so Terraform is its ONLY writer — nothing to fight over.
}
