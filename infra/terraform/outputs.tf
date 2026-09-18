# These outputs exist after the FIRST apply (deploy_apps = false) — the app URLs
# are computed from the environment's default domain, so you can bake them into
# the webapp image before the apps exist.

output "resource_group" {
  value = azurerm_resource_group.main.name
}

output "acr_login_server" {
  value = azurerm_container_registry.main.login_server
}

output "acr_name" {
  value = azurerm_container_registry.main.name
}

output "cosmos_endpoint" {
  value = azurerm_cosmosdb_account.main.endpoint
}

# The single public API entry point (environment rule-based routing FQDN).
output "api_url" {
  value = local.api_url
}

output "candidate_internal_url" {
  value = local.candidate_internal_url
}

output "job_internal_url" {
  value = local.job_internal_url
}

output "application_internal_url" {
  value = local.application_internal_url
}

output "webapp_url" {
  value = local.webapp_url
}
