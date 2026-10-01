output "tenant_id" {
  value = var.tenant_id
}

output "web_client_id" {
  value = azuread_application.web.client_id
}

output "api_client_ids" {
  value = { for key, app in azuread_application.api : key => app.client_id }
}

output "api_scopes" {
  value = { for key, app in azuread_application.api : key => "api://${app.client_id}/${local.scope_name}" }
}

# Ready to paste into src/WebApp/.env (public identifiers, safe to commit).
output "webapp_env" {
  value = <<-EOT
    VITE_AUTH_TENANT_ID=${var.tenant_id}
    VITE_AUTH_CLIENT_ID=${azuread_application.web.client_id}
    VITE_API_SCOPE_CANDIDATES=api://${azuread_application.api["candidate"].client_id}/${local.scope_name}
    VITE_API_SCOPE_JOBS=api://${azuread_application.api["job"].client_id}/${local.scope_name}
    VITE_API_SCOPE_APPLICATIONS=api://${azuread_application.api["application"].client_id}/${local.scope_name}
  EOT
}

# For the root .env (docker compose) or `dotnet user-secrets` — NEVER commit it.
output "application_api_client_secret" {
  value     = azuread_application_password.application_local_dev.value
  sensitive = true
}

output "test_users" {
  value = {
    for key, user in azuread_user.test : key => {
      user_principal_name = user.user_principal_name
      password            = random_password.test_user[key].result
    }
  }
  sensitive = true
}
