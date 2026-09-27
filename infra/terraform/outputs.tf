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

output "cosmos_endpoint" {
  value = azurerm_cosmosdb_account.main.endpoint
}

# What the Cosmos hostname should resolve to from inside the environment.
output "cosmos_private_ip" {
  value = azurerm_private_endpoint.cosmos.private_service_connection[0].private_ip_address
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
