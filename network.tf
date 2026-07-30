resource "azurerm_resource_group" "main"{
    name = "rg-3tier-app"
    location = "westus2"
}

resource "azurerm_virtual_network" "main"{
    name = "vnet_3tier"
    address_space = ["10.0.0.0/16"]
    resource_group_name = azurerm_resource_group.main.name
    location = azurerm_resource_group.main.location
}

resource "azurerm_subnet" "web" {
  name = "snet-web"
  virtual_network_name = azurerm_virtual_network.main.name  
  resource_group_name = azurerm_resource_group.main.name
  address_prefixes = ["10.0.1.0/24"]
}

resource "azurerm_subnet" "app" {
  name                 = "snet-app"
  resource_group_name  = azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = ["10.0.2.0/24"]
  delegation {
    name = "app-servive-delegation"
    service_delegation {
      name = "Microsoft.Web/serverFarms"
      actions = ["Microsoft.Network/virtualNetworks/subnets/action"]
    }
  }
}

//need Private Endpoint to bring PaaS inside VNET
resource "azurerm_subnet" "data" {
  name                 = "snet-data"
  resource_group_name  = azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = ["10.0.3.0/24"]

  private_endpoint_network_policies = "Enabled"
}

//need Private Endpoint to bring PaaS inside VNET
resource "azurerm_subnet" "keyvault" {
  name                 = "snet-keyvault"
  resource_group_name  = azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = ["10.0.4.0/24"]

  private_endpoint_network_policies = "Enabled"
}

resource "azurerm_network_security_group" "web" {
  name = "nsg_web"
  location = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
}

//nsg does nothing unless its linked to NIC or subnet
resource "azurerm_subnet_network_security_group_association" "web" {
  subnet_id = azurerm_subnet.web.id
  network_security_group_id = azurerm_network_security_group.web.id
}

resource "azurerm_network_security_group" "app" {
  name                = "nsg-app"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
}

resource "azurerm_subnet_network_security_group_association" "app" {
  subnet_id                 = azurerm_subnet.app.id
  network_security_group_id = azurerm_network_security_group.app.id
}

resource "azurerm_network_security_group" "data" {
  name                = "nsg-data"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
}

resource "azurerm_subnet_network_security_group_association" "data" {
  subnet_id                 = azurerm_subnet.data.id
  network_security_group_id = azurerm_network_security_group.data.id
}

resource "azurerm_network_security_group" "keyvault" {
  name                = "nsg-keyvault"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
}

resource "azurerm_subnet_network_security_group_association" "keyvault" {
  subnet_id                 = azurerm_subnet.keyvault.id
  network_security_group_id = azurerm_network_security_group.keyvault.id
}

resource "azurerm_network_security_rule" "app_allow_from_web"{
  name = "allow-web-inbound"
  priority = 100
  direction = "Inbound"
  access = "Allow"
  protocol = "Tcp"
  source_port_range = "*"
  destination_port_range = "443"
  source_address_prefix = azurerm_subnet.web.address_prefixes[0]
  destination_address_prefix  = azurerm_subnet.app.address_prefixes[0]
  resource_group_name = azurerm_resource_group.main.name
  network_security_group_name = azurerm_network_security_group.app.name
}

resource "azurerm_network_security_rule" "data_allow_from_app" {
  name                        = "allow-app-inbound"
  priority                    = 100
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_port_range           = "*"
  destination_port_range      = "1433"
  source_address_prefix       = azurerm_subnet.app.address_prefixes[0]
  destination_address_prefix  = azurerm_subnet.data.address_prefixes[0]
  resource_group_name         = azurerm_resource_group.main.name
  network_security_group_name = azurerm_network_security_group.data.name
}

resource "azurerm_network_security_rule" "keyvault_allow_from_app" {
  name                        = "allow-app-inbound"
  priority                    = 100
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_port_range           = "*"
  destination_port_range      = "443"
  source_address_prefix       = azurerm_subnet.app.address_prefixes[0]
  destination_address_prefix  = azurerm_subnet.keyvault.address_prefixes[0]
  resource_group_name         = azurerm_resource_group.main.name
  network_security_group_name = azurerm_network_security_group.keyvault.name
}

resource "azurerm_network_security_rule" "app_deny_all" {
  name                         = "deny-all-other-inbound"
  priority                     = 4096
  direction                    = "Inbound"
  access                       = "Deny"
  protocol                     = "*"
  source_port_range            = "*"
  destination_port_range       = "*"
  source_address_prefix        = "*"
  destination_address_prefix   = "*"
  resource_group_name          = azurerm_resource_group.main.name
  network_security_group_name  = azurerm_network_security_group.app.name
}

resource "azurerm_network_security_rule" "data_deny_all" {
  name                         = "deny-all-other-inbound"
  priority                     = 4096
  direction                    = "Inbound"
  access                       = "Deny"
  protocol                     = "*"
  source_port_range            = "*"
  destination_port_range       = "*"
  source_address_prefix        = "*"
  destination_address_prefix   = "*"
  resource_group_name          = azurerm_resource_group.main.name
  network_security_group_name  = azurerm_network_security_group.data.name
}

resource "azurerm_network_security_rule" "keyvault_deny_all" {
  name                         = "deny-all-other-inbound"
  priority                     = 4096
  direction                    = "Inbound"
  access                       = "Deny"
  protocol                     = "*"
  source_port_range            = "*"
  destination_port_range       = "*"
  source_address_prefix        = "*"
  destination_address_prefix   = "*"
  resource_group_name          = azurerm_resource_group.main.name
  network_security_group_name  = azurerm_network_security_group.keyvault.name
}