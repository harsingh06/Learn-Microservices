# ---------------------------------------------------------------------------
# CONTRACT for the service stacks (src/<Service>/infra read these through
# terraform_remote_state). Renaming or reshaping one breaks every service —
# treat changes here like a breaking API change.
# ---------------------------------------------------------------------------

# Everything infra/modules/container-app-service needs to place an app.
output "container_app_platform" {
  value = {
    resource_group_name = azurerm_resource_group.main.name
    resource_group_id   = azurerm_resource_group.main.id
    environment_id      = azurerm_container_app_environment.main.id
    default_domain      = azurerm_container_app_environment.main.default_domain
    registry_server     = azurerm_container_registry.main.login_server
    identity_id         = azurerm_user_assigned_identity.apps.id
    tags                = local.tags
  }
}

# Container app names per component — the naming convention stays here.
output "app_names" {
  value = local.app_names
}

# In-environment URLs, for service-to-service calls (ApplicationService).
output "internal_urls" {
  value = {
    for component, name in local.app_names :
    component => "https://${name}.internal.${azurerm_container_app_environment.main.default_domain}"
  }
}

output "cosmos_endpoint" {
  value = azurerm_cosmosdb_account.main.endpoint
}

# Until the apps move to managed identity (BACKLOG.md), they authenticate to
# Cosmos with the account key.
output "cosmos_primary_key" {
  value     = azurerm_cosmosdb_account.main.primary_key
  sensitive = true
}

# ---------------------------------------------------------------------------
# For people and pipelines.
# ---------------------------------------------------------------------------

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

# The site: the custom domain if set, otherwise Front Door's own hostname.
output "site_url" {
  value = var.custom_domain != "" ? "https://${var.custom_domain}" : "https://${azurerm_cdn_frontdoor_endpoint.main.host_name}"
}

# The CNAME target for the custom domain.
output "frontdoor_hostname" {
  value = azurerm_cdn_frontdoor_endpoint.main.host_name
}

# The TXT record Front Door needs before it issues the managed certificate.
output "custom_domain_validation" {
  value = var.custom_domain == "" ? null : {
    record = "_dnsauth.${var.custom_domain}"
    type   = "TXT"
    value  = azurerm_cdn_frontdoor_custom_domain.site[0].validation_token
  }
}

# Front Door's origin. Also reachable directly (bypasses the WAF) — BACKLOG.md.
output "route_url" {
  value = "https://${local.route_config_fqdn}"
}

# Route rules waiting for their app to exist (fresh environment): deploy the
# service, then re-run this stack.
output "pending_routes" {
  value = local.pending_routes
}
