# WebApp's own stack: its container app, and nothing else. Shared and stateful
# resources come from the platform stack (infra/platform) through its outputs.

data "terraform_remote_state" "platform" {
  backend = "azurerm"
  config = {
    resource_group_name  = "ats-tfstate-rg"
    storage_account_name = "atstfstate4sqlo"
    container_name       = "tfstate"
    key                  = "ats.tfstate"
  }
}

locals {
  platform = data.terraform_remote_state.platform.outputs
}

module "app" {
  source = "../../../infra/modules/container-app-service"

  name           = local.platform.app_names.webapp
  platform       = local.platform.container_app_platform
  container_name = "webapp"
  image          = var.image
  target_port    = 80

  # No env vars: the bundle calls relative /api paths on its own origin.
}

output "app_name" {
  value = module.app.name
}
