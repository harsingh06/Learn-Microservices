# One-time migration: adopt the app the platform stack used to manage (it now
# forgets it — infra/platform/migrations.tf). Nothing is recreated.
#
# Delete this file after the first successful apply on main: on a brand-new
# environment there is nothing to import, and the import would fail.
import {
  to = module.app.azurerm_container_app.this
  id = "${local.platform.container_app_platform.resource_group_id}/providers/Microsoft.App/containerApps/${local.platform.app_names.application}"
}
