# The browser app: a public client (no secret) using auth code + PKCE via MSAL.
# It signs users in and gets an access token per API.

data "azuread_application_published_app_ids" "well_known" {}

data "azuread_service_principal" "msgraph" {
  client_id = data.azuread_application_published_app_ids.well_known.result["MicrosoftGraph"]
}

locals {
  # Standard OpenID Connect sign-in scopes (ID token, profile, refresh tokens).
  sign_in_scopes = ["openid", "profile", "offline_access"]
}

resource "azuread_application" "web" {
  display_name     = "ATS Web"
  sign_in_audience = "AzureADMyOrg"
  owners           = local.owners

  single_page_application {
    redirect_uris = var.spa_redirect_uris
  }

  # Same roles as the APIs, so the ID token tells the UI what to show.
  dynamic "app_role" {
    for_each = local.roles
    content {
      id                   = random_uuid.role["web-${app_role.key}"].result
      value                = app_role.key
      display_name         = app_role.key
      description          = app_role.value
      allowed_member_types = ["User"]
      enabled              = true
    }
  }

  required_resource_access {
    resource_app_id = data.azuread_application_published_app_ids.well_known.result["MicrosoftGraph"]

    dynamic "resource_access" {
      for_each = local.sign_in_scopes
      content {
        id   = data.azuread_service_principal.msgraph.oauth2_permission_scope_ids[resource_access.value]
        type = "Scope"
      }
    }
  }

  dynamic "required_resource_access" {
    for_each = local.apis
    content {
      resource_app_id = azuread_application.api[required_resource_access.key].client_id
      resource_access {
        id   = random_uuid.scope[required_resource_access.key].result
        type = "Scope"
      }
    }
  }
}

resource "azuread_service_principal" "web" {
  client_id = azuread_application.web.client_id
  owners    = local.owners
  # Only users with a role can sign in to the app at all.
  app_role_assignment_required = true
}

# Tenant-wide consent for everything the web app asks for: no consent prompts.
resource "azuread_service_principal_delegated_permission_grant" "web_sign_in" {
  service_principal_object_id          = azuread_service_principal.web.object_id
  resource_service_principal_object_id = data.azuread_service_principal.msgraph.object_id
  claim_values                         = local.sign_in_scopes
}

resource "azuread_service_principal_delegated_permission_grant" "web_apis" {
  for_each = local.apis

  service_principal_object_id          = azuread_service_principal.web.object_id
  resource_service_principal_object_id = azuread_service_principal.api[each.key].object_id
  claim_values                         = [local.scope_name]
}
