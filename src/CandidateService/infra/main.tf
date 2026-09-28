# CandidateService's own stack: its container app, and nothing else. Shared and stateful
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

  name           = local.platform.app_names.candidate
  platform       = local.platform.container_app_platform
  container_name = "candidate-service"
  image          = var.image
  target_port    = 8080

  # Cosmos database/container are the PLATFORM's (infra/platform/cosmos.tf);
  # the app only gets the endpoint and key. Database and container names come
  # from appsettings.json.
  secrets = {
    "cosmos-key" = local.platform.cosmos_primary_key
  }
  env = {
    Cosmos__Endpoint = { value = local.platform.cosmos_endpoint }
    Cosmos__Key      = { secret = "cosmos-key" }
  }
}

output "app_name" {
  value = module.app.name
}
