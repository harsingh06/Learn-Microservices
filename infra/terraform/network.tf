# Private networking: one VNet, two subnets.
#   snet-aca — the Container Apps environment's infrastructure subnet
#   snet-pe  — private endpoints (today: Cosmos DB only)
#
# Why: with Cosmos public access disabled, a leaked account key alone is no longer
# enough — the caller must also be inside this VNet. Private endpoints were chosen
# over service endpoints because traffic then never touches a public IP.

resource "azurerm_virtual_network" "main" {
  name                = "${var.prefix}-vnet"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  address_space       = ["10.0.0.0/16"]
}

# Workload-profiles environment (the Azure default for new environments; see the
# Consumption profile in main.tf): the subnet MUST be delegated to
# Microsoft.App/environments and nothing else may live in it. /27 is the minimum;
# a /21 leaves ample room for replicas and the platform's own reserved addresses.
resource "azurerm_subnet" "aca" {
  name                 = "snet-aca"
  resource_group_name  = azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = ["10.0.0.0/21"] # 10.0.0.0 - 10.0.7.255

  delegation {
    name = "aca-environment"
    service_delegation {
      name    = "Microsoft.App/environments"
      actions = ["Microsoft.Network/virtualNetworks/subnets/join/action"]
    }
  }
}

resource "azurerm_subnet" "private_endpoints" {
  name                 = "snet-pe"
  resource_group_name  = azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = ["10.0.8.0/27"] # first block after snet-aca
}

# DNS is what makes a private endpoint transparent to the apps. Public DNS answers
#   <account>.documents.azure.com -> CNAME <account>.privatelink.documents.azure.com
# and inside the VNet this linked zone answers the privatelink name with the
# endpoint's private IP. The apps keep using the normal endpoint URL, unchanged.
resource "azurerm_private_dns_zone" "cosmos" {
  name                = "privatelink.documents.azure.com"
  resource_group_name = azurerm_resource_group.main.name
}

resource "azurerm_private_dns_zone_virtual_network_link" "cosmos" {
  name                  = "${var.prefix}-cosmos-dns-link"
  resource_group_name   = azurerm_resource_group.main.name
  private_dns_zone_name = azurerm_private_dns_zone.cosmos.name
  virtual_network_id    = azurerm_virtual_network.main.id
  registration_enabled  = false
}

resource "azurerm_private_endpoint" "cosmos" {
  name                = "${var.prefix}-cosmos-pe"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  subnet_id           = azurerm_subnet.private_endpoints.id

  private_service_connection {
    name                           = "${var.prefix}-cosmos-psc"
    private_connection_resource_id = azurerm_cosmosdb_account.main.id
    subresource_names              = ["Sql"] # the NoSQL (SQL API) endpoint
    is_manual_connection           = false
  }

  # Registers A records in the zone for the global AND regional hostnames.
  private_dns_zone_group {
    name                 = "cosmos"
    private_dns_zone_ids = [azurerm_private_dns_zone.cosmos.id]
  }
}
