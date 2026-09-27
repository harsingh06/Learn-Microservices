# These outputs exist after the FIRST apply (deploy_apps = false) — the URLs are
# computed from the environment's default domain before the apps exist.

output "resource_group" {
  value = azurerm_resource_group.main.name
}

output "acr_login_server" {
  value = azurerm_container_registry.main.login_server
}

output "acr_name" {
  value = azurerm_container_registry.main.name
}

output "environment_name" {
  value = azurerm_container_app_environment.main.name
}

# Container app names, for the pipelines' `az containerapp update --name`.
output "app_names" {
  value = local.app_names
}

output "cosmos_endpoint" {
  value = azurerm_cosmosdb_account.main.endpoint
}

# The site: webapp at /, APIs at /api/<resource>/* — the custom domain if set.
output "site_url" {
  value = local.site_url
}

# The route config's default FQDN: same entry point, always available (also the
# CNAME target for the custom domain).
output "route_url" {
  value = local.route_url
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
