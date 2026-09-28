# Rule-based routing (PREVIEW): the environment's single public entry point and
# Front Door's origin (frontdoor.tf). azurerm has no resource for this yet, hence
# azapi. The PLATFORM owns it: which paths are public, and which app serves them,
# is a platform decision — a new service gets its rule through a platform PR.
#
# Azure rejects a rule whose target app does not exist yet, and the apps are
# created by their own service pipelines (src/<Service>/infra). So rules are only
# emitted for apps that already exist; the rest show up in the `pending_routes`
# output. A brand-new environment therefore needs this stack applied twice:
# platform -> service pipelines -> platform again (see DEPLOY.md).

locals {
  # Matched IN ORDER: the /api prefixes first, the "/" catch-all for the webapp
  # last — otherwise it would swallow /api too.
  route_rules = [
    {
      description = "Candidate service"
      prefix      = "/api/candidates"
      route       = { match = { prefix = "/api/candidates" }, action = { prefixRewrite = "/candidates" } }
      app         = local.app_names.candidate
    },
    {
      description = "Job service"
      prefix      = "/api/jobs"
      route       = { match = { prefix = "/api/jobs" }, action = { prefixRewrite = "/jobs" } }
      app         = local.app_names.job
    },
    {
      description = "Application service"
      prefix      = "/api/applications"
      route       = { match = { prefix = "/api/applications" }, action = { prefixRewrite = "/applications" } }
      app         = local.app_names.application
    },
    {
      # Catch-all: everything else is the SPA (nginx falls back to index.html).
      description = "Webapp"
      prefix      = "/"
      route       = { match = { prefix = "/" } } # no rewrite
      app         = local.app_names.webapp
    },
  ]

  existing_apps  = toset(data.azapi_resource_list.apps.output.names)
  active_rules   = [for r in local.route_rules : r if contains(local.existing_apps, r.app)]
  pending_routes = [for r in local.route_rules : "${r.prefix} -> ${r.app}" if !contains(local.existing_apps, r.app)]
}

# Read at plan time, so the route config always matches the apps that exist.
data "azapi_resource_list" "apps" {
  type      = "Microsoft.App/containerApps@2024-03-01"
  parent_id = azurerm_resource_group.main.id

  response_export_values = {
    names = "value[].name"
  }
}

resource "azapi_resource" "routes" {
  # An empty rule list isn't a useful route config; skip it until an app exists.
  count = length(local.active_rules) > 0 ? 1 : 0

  type      = "Microsoft.App/managedEnvironments/httpRouteConfigs@2025-10-02-preview"
  name      = local.names.route_config
  parent_id = azurerm_container_app_environment.main.id

  body = {
    properties = {
      # No custom domain here: ats.harsingh.com lives on Front Door, which
      # forwards to this config's default FQDN. Explicitly empty — azapi ignores
      # properties that are simply left out, so omitting it wouldn't remove one.
      customDomains = []
      rules = [
        for r in local.active_rules : {
          description = r.description
          routes      = [r.route]
          targets     = [{ containerApp = r.app }]
        }
      ]
    }
  }
}
