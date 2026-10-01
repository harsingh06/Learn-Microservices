# One app registration per API (its own token audience), one for the browser app.
#
#   ats-web (SPA) ──signs users in──► tokens for each API ──► CandidateService / JobService / ApplicationService
#   ats-application-api ──On-Behalf-Of──► tokens for ats-candidate-api / ats-job-api
#
# Every registration defines the same two app roles. A user's roles are assigned
# per app, so the token for each API carries the roles assigned on THAT API.

data "azuread_client_config" "current" {}

locals {
  apis = {
    candidate   = "ATS Candidate API"
    job         = "ATS Job API"
    application = "ATS Application API"
  }

  roles = {
    Recruiter     = "Manages candidates and jobs, and submits applications."
    HiringManager = "Reviews applications: moves them to InReview, Accepted or Rejected."
  }

  # Every registration that carries the roles: the three APIs and the web app (the
  # ID token's roles drive what the UI shows; the APIs enforce it regardless).
  role_apps = concat(keys(local.apis), ["web"])

  scope_name = "access_as_user"
  owners     = [data.azuread_client_config.current.object_id]
}

# Stable IDs for scopes and app roles (Entra needs a GUID per definition).
resource "random_uuid" "scope" {
  for_each = local.apis
}

resource "random_uuid" "role" {
  for_each = { for pair in setproduct(local.role_apps, keys(local.roles)) : "${pair[0]}-${pair[1]}" => pair }
}

# ---------------------------------------------------------------------------
# The three APIs
# ---------------------------------------------------------------------------
resource "azuread_application" "api" {
  for_each = local.apis

  display_name     = each.value
  sign_in_audience = "AzureADMyOrg" # this tenant only
  owners           = local.owners

  api {
    # v2 tokens: aud = this app's client ID, issuer = .../{tenant}/v2.0
    requested_access_token_version = 2

    oauth2_permission_scope {
      id                         = random_uuid.scope[each.key].result
      value                      = local.scope_name
      type                       = "User"
      enabled                    = true
      admin_consent_display_name = "Access ${each.value} as the signed-in user"
      admin_consent_description  = "Lets the app call ${each.value} on behalf of the signed-in user."
      user_consent_display_name  = "Access ${each.value} as you"
      user_consent_description   = "Lets the app call ${each.value} on your behalf."
    }
  }

  dynamic "app_role" {
    for_each = local.roles
    content {
      id                   = random_uuid.role["${each.key}-${app_role.key}"].result
      value                = app_role.key
      display_name         = app_role.key
      description          = app_role.value
      allowed_member_types = ["User"]
      enabled              = true
    }
  }

  # Managed by separate resources below: the identifier URI needs this app's own
  # client ID, and ApplicationService's API permissions reference its sibling APIs
  # (inline, that would be a cycle inside this for_each).
  lifecycle {
    ignore_changes = [identifier_uris, required_resource_access]
  }
}

# api://<client-id> — the prefix of each API's scope, e.g. api://<id>/access_as_user.
resource "azuread_application_identifier_uri" "api" {
  for_each = local.apis

  application_id = azuread_application.api[each.key].id
  identifier_uri = "api://${azuread_application.api[each.key].client_id}"
}

resource "azuread_service_principal" "api" {
  for_each = local.apis

  client_id = azuread_application.api[each.key].client_id
  owners    = local.owners
  # Only users assigned a role can get a token for this API at all.
  app_role_assignment_required = true
}

# ---------------------------------------------------------------------------
# On-Behalf-Of: ApplicationService calls Candidate/Job APIs as the signed-in user
# ---------------------------------------------------------------------------
resource "azuread_application_api_access" "obo" {
  for_each = toset(["candidate", "job"])

  application_id = azuread_application.api["application"].id
  api_client_id  = azuread_application.api[each.key].client_id
  scope_ids      = [random_uuid.scope[each.key].result]
}

# Tenant-wide (admin) consent, so the exchange never needs a user prompt.
resource "azuread_service_principal_delegated_permission_grant" "obo" {
  for_each = toset(["candidate", "job"])

  service_principal_object_id          = azuread_service_principal.api["application"].object_id
  resource_service_principal_object_id = azuread_service_principal.api[each.key].object_id
  claim_values                         = [local.scope_name]
}

# ApplicationService's credentials for the exchange (it's a confidential client):
# - local dev: a client secret (goes in the root .env / user-secrets, never in git);
# - Azure: its managed identity, trusted through a federated credential — no secret.
resource "azuread_application_password" "application_local_dev" {
  application_id = azuread_application.api["application"].id
  display_name   = "local-dev"
}

resource "azuread_application_federated_identity_credential" "application_managed_identity" {
  count = var.application_managed_identity_principal_id == "" ? 0 : 1

  application_id = azuread_application.api["application"].id
  display_name   = "aca-managed-identity"
  description    = "ApplicationService's user-assigned managed identity in Azure Container Apps."
  audiences      = ["api://AzureADTokenExchange"]
  issuer         = "https://login.microsoftonline.com/${var.tenant_id}/v2.0"
  subject        = var.application_managed_identity_principal_id
}

# Dev convenience: lets the Azure CLI request tokens for the APIs
# (az account get-access-token --scope api://<id>/access_as_user) — used by the
# .http files and for testing without the browser.
resource "azuread_application_pre_authorized" "azure_cli" {
  for_each = local.apis

  application_id       = azuread_application.api[each.key].id
  authorized_client_id = "04b07795-8ddb-461a-bbee-02f9e1bf7b46" # Azure CLI
  permission_ids       = [random_uuid.scope[each.key].result]
}
