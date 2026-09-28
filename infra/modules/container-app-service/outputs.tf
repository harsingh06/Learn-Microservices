output "name" {
  value = azurerm_container_app.this.name
}

output "id" {
  value = azurerm_container_app.this.id
}

# Reachable only inside the environment.
output "internal_url" {
  value = "https://${azurerm_container_app.this.name}.internal.${var.platform.default_domain}"
}
