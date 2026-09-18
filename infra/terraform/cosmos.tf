# Real Cosmos DB replacing the local emulator. Database/container names must match
# what each service's appsettings.json expects — only endpoint+key are overridden
# via environment variables on the container apps.

resource "azurerm_cosmosdb_account" "main" {
  name                = "${var.prefix}-${random_string.suffix.result}-cosmos"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  offer_type          = "Standard"
  kind                = "GlobalDocumentDB"

  # Only ONE free-tier account is allowed per subscription; apply fails if taken.
  free_tier_enabled = true

  consistency_policy {
    consistency_level = "Session"
  }

  geo_location {
    location          = var.location
    failover_priority = 0
  }
}

# One database per service ("service owns its data" — same boundary as local dev).
# Throughput is shared at the database level. Cost note: free tier covers 1000 RU/s,
# 3 x 400 = 1200 RU/s, so ~200 RU/s is billed (~USD 12/month) while deployed.

resource "azurerm_cosmosdb_sql_database" "candidates" {
  name                = "candidates-db"
  resource_group_name = azurerm_resource_group.main.name
  account_name        = azurerm_cosmosdb_account.main.name
  throughput          = var.cosmos_database_throughput
}

resource "azurerm_cosmosdb_sql_database" "jobs" {
  name                = "jobs-db"
  resource_group_name = azurerm_resource_group.main.name
  account_name        = azurerm_cosmosdb_account.main.name
  throughput          = var.cosmos_database_throughput
}

resource "azurerm_cosmosdb_sql_database" "applications" {
  name                = "applications-db"
  resource_group_name = azurerm_resource_group.main.name
  account_name        = azurerm_cosmosdb_account.main.name
  throughput          = var.cosmos_database_throughput
}

resource "azurerm_cosmosdb_sql_container" "candidates" {
  name                = "candidates"
  resource_group_name = azurerm_resource_group.main.name
  account_name        = azurerm_cosmosdb_account.main.name
  database_name       = azurerm_cosmosdb_sql_database.candidates.name
  partition_key_paths = ["/id"]
}

resource "azurerm_cosmosdb_sql_container" "jobs" {
  name                = "jobs"
  resource_group_name = azurerm_resource_group.main.name
  account_name        = azurerm_cosmosdb_account.main.name
  database_name       = azurerm_cosmosdb_sql_database.jobs.name
  partition_key_paths = ["/id"]
}

resource "azurerm_cosmosdb_sql_container" "applications" {
  name                = "applications"
  resource_group_name = azurerm_resource_group.main.name
  account_name        = azurerm_cosmosdb_account.main.name
  database_name       = azurerm_cosmosdb_sql_database.applications.name
  partition_key_paths = ["/id"]
}
