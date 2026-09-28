# Azure Front Door (Standard): the global edge in front of the environment.
#
#   user -> Front Door (ats.harsingh.com, managed TLS, WAF, /assets cache)
#        -> route config default FQDN (routing.tf) -> internal-only apps
#
# Front Door holds the custom domain and its certificate, both in Terraform (the
# route config no longer has a domain). Its origin is a HOSTNAME, so it doesn't
# care whether the apps exist yet — no ordering problem.
#
# Standard vs Premium: Standard reaches the route config over the public internet
# (fine, the environment has public ingress). Premium (~$330/mo) adds the managed
# OWASP WAF rule set and Private Link. Known gap on Standard: the route config's
# own FQDN stays publicly reachable, so the WAF can be bypassed by anyone who
# knows it (BACKLOG.md).

locals {
  route_config_fqdn = "${local.names.route_config}.${azurerm_container_app_environment.main.default_domain}"
}

resource "azurerm_cdn_frontdoor_profile" "main" {
  name                = local.names.frontdoor
  resource_group_name = azurerm_resource_group.main.name
  sku_name            = "Standard_AzureFrontDoor"
  tags                = local.tags
}

# The *.azurefd.net hostname — also the CNAME target for the custom domain.
resource "azurerm_cdn_frontdoor_endpoint" "main" {
  name                     = local.names.frontdoor_endpoint
  cdn_frontdoor_profile_id = azurerm_cdn_frontdoor_profile.main.id
  tags                     = local.tags
}

# One origin, so health probes are pointless — and left off on purpose: a probe
# every few seconds from each Front Door POP would keep the scale-to-zero apps
# permanently awake (and billed).
resource "azurerm_cdn_frontdoor_origin_group" "main" {
  name                     = "og-route-config"
  cdn_frontdoor_profile_id = azurerm_cdn_frontdoor_profile.main.id

  load_balancing {}
}

resource "azurerm_cdn_frontdoor_origin" "route_config" {
  name                          = "route-config"
  cdn_frontdoor_origin_group_id = azurerm_cdn_frontdoor_origin_group.main.id
  enabled                       = true

  host_name = local.route_config_fqdn
  # The environment's ingress picks the destination by Host header, so it must
  # be the route config's own FQDN — not the user's hostname.
  origin_host_header             = local.route_config_fqdn
  certificate_name_check_enabled = true
  http_port                      = 80
  https_port                     = 443
}

resource "azurerm_cdn_frontdoor_custom_domain" "site" {
  count = var.custom_domain != "" ? 1 : 0

  name                     = replace(var.custom_domain, ".", "-")
  cdn_frontdoor_profile_id = azurerm_cdn_frontdoor_profile.main.id
  host_name                = var.custom_domain

  # Free, auto-renewing certificate. Issued once Front Door sees the _dnsauth TXT
  # record (terraform output custom_domain_validation) at your DNS provider.
  tls {
    certificate_type = "ManagedCertificate"
  }
}

locals {
  custom_domain_ids = [for d in azurerm_cdn_frontdoor_custom_domain.site : d.id]
}

# Everything: forwarded as-is, never cached (API responses and index.html must
# always be fresh).
resource "azurerm_cdn_frontdoor_route" "site" {
  name                          = "site"
  cdn_frontdoor_endpoint_id     = azurerm_cdn_frontdoor_endpoint.main.id
  cdn_frontdoor_origin_group_id = azurerm_cdn_frontdoor_origin_group.main.id
  cdn_frontdoor_origin_ids      = [azurerm_cdn_frontdoor_origin.route_config.id]

  patterns_to_match      = ["/*"]
  supported_protocols    = ["Http", "Https"]
  https_redirect_enabled = true
  forwarding_protocol    = "HttpsOnly"
  link_to_default_domain = true

  cdn_frontdoor_custom_domain_ids = local.custom_domain_ids
}

# The webapp's build output: Vite puts a content hash in every file name under
# /assets, so a changed file is a NEW URL and caching them at the edge is safe.
resource "azurerm_cdn_frontdoor_route" "assets" {
  name                          = "assets"
  cdn_frontdoor_endpoint_id     = azurerm_cdn_frontdoor_endpoint.main.id
  cdn_frontdoor_origin_group_id = azurerm_cdn_frontdoor_origin_group.main.id
  cdn_frontdoor_origin_ids      = [azurerm_cdn_frontdoor_origin.route_config.id]

  patterns_to_match      = ["/assets/*"]
  supported_protocols    = ["Http", "Https"]
  https_redirect_enabled = true
  forwarding_protocol    = "HttpsOnly"
  link_to_default_domain = true

  cdn_frontdoor_custom_domain_ids = local.custom_domain_ids

  cache {
    query_string_caching_behavior = "IgnoreQueryString"
    compression_enabled           = true
    content_types_to_compress     = ["application/javascript", "text/css", "image/svg+xml"]
  }
}

# Required alongside the routes' custom domain ids — without it the domain and
# the routes drift against each other on every plan.
resource "azurerm_cdn_frontdoor_custom_domain_association" "site" {
  count = var.custom_domain != "" ? 1 : 0

  cdn_frontdoor_custom_domain_id = azurerm_cdn_frontdoor_custom_domain.site[0].id
  cdn_frontdoor_route_ids = [
    azurerm_cdn_frontdoor_route.site.id,
    azurerm_cdn_frontdoor_route.assets.id,
  ]
}

# WAF, Standard tier: custom rules only (the managed OWASP rule set is Premium).
resource "azurerm_cdn_frontdoor_firewall_policy" "main" {
  name                = local.names.waf_policy
  resource_group_name = azurerm_resource_group.main.name
  sku_name            = azurerm_cdn_frontdoor_profile.main.sku_name
  enabled             = true
  mode                = "Prevention"
  tags                = local.tags

  # Per client IP: more than 300 API calls in a minute gets blocked for the rest
  # of that minute. Generous for a human, a brake on scripts hammering Cosmos.
  custom_rule {
    name                           = "RateLimitApi"
    enabled                        = true
    priority                       = 100
    type                           = "RateLimitRule"
    rate_limit_duration_in_minutes = 1
    rate_limit_threshold           = 300
    action                         = "Block"

    match_condition {
      match_variable = "RequestUri"
      operator       = "Contains"
      match_values   = ["/api/"]
    }
  }
}

resource "azurerm_cdn_frontdoor_security_policy" "main" {
  name                     = "waf-${local.suffix}"
  cdn_frontdoor_profile_id = azurerm_cdn_frontdoor_profile.main.id

  security_policies {
    firewall {
      cdn_frontdoor_firewall_policy_id = azurerm_cdn_frontdoor_firewall_policy.main.id

      association {
        patterns_to_match = ["/*"]

        domain {
          cdn_frontdoor_domain_id = azurerm_cdn_frontdoor_endpoint.main.id
        }

        dynamic "domain" {
          for_each = local.custom_domain_ids
          content {
            cdn_frontdoor_domain_id = domain.value
          }
        }
      }
    }
  }
}
