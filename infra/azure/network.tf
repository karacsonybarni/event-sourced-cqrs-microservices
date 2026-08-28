resource "azurerm_virtual_network" "runtime" {
  name                = "${local.name_prefix}-vnet"
  address_space       = ["10.42.0.0/16"]
  location            = azurerm_resource_group.runtime.location
  resource_group_name = azurerm_resource_group.runtime.name
  tags                = local.tags
}

resource "azurerm_subnet" "runtime" {
  name                 = "platform"
  resource_group_name  = azurerm_resource_group.runtime.name
  virtual_network_name = azurerm_virtual_network.runtime.name
  address_prefixes     = ["10.42.1.0/24"]
}

resource "azurerm_subnet" "functions" {
  name                 = "serverless"
  resource_group_name  = azurerm_resource_group.runtime.name
  virtual_network_name = azurerm_virtual_network.runtime.name
  address_prefixes     = ["10.42.2.0/27"]

  delegation {
    name = "flex-consumption"

    service_delegation {
      name    = "Microsoft.App/environments"
      actions = ["Microsoft.Network/virtualNetworks/subnets/join/action"]
    }
  }
}

resource "azurerm_subnet" "private_endpoints" {
  name                              = "private-endpoints"
  resource_group_name               = azurerm_resource_group.runtime.name
  virtual_network_name              = azurerm_virtual_network.runtime.name
  address_prefixes                  = ["10.42.3.0/28"]
  private_endpoint_network_policies = "Disabled"
}

resource "azurerm_network_security_group" "runtime" {
  name                = "${local.name_prefix}-nsg"
  location            = azurerm_resource_group.runtime.location
  resource_group_name = azurerm_resource_group.runtime.name
  tags                = local.tags
}

resource "azurerm_network_security_rule" "http" {
  name                        = "Allow-HTTP"
  priority                    = 100
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_port_range           = "*"
  destination_port_range      = "80"
  source_address_prefix       = "Internet"
  destination_address_prefix  = "*"
  resource_group_name         = azurerm_resource_group.runtime.name
  network_security_group_name = azurerm_network_security_group.runtime.name
}

resource "azurerm_network_security_rule" "https" {
  name                        = "Allow-HTTPS"
  priority                    = 110
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_port_range           = "*"
  destination_port_range      = "443"
  source_address_prefix       = "Internet"
  destination_address_prefix  = "*"
  resource_group_name         = azurerm_resource_group.runtime.name
  network_security_group_name = azurerm_network_security_group.runtime.name
}

resource "azurerm_network_security_rule" "function_kafka" {
  name                        = "Allow-Function-Kafka"
  priority                    = 120
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_port_range           = "*"
  destination_port_range      = "9094"
  source_address_prefix       = azurerm_subnet.functions.address_prefixes[0]
  destination_address_prefix  = "10.42.1.4"
  resource_group_name         = azurerm_resource_group.runtime.name
  network_security_group_name = azurerm_network_security_group.runtime.name
}

resource "azurerm_public_ip" "runtime" {
  name                = "${local.name_prefix}-ip"
  location            = azurerm_resource_group.runtime.location
  resource_group_name = azurerm_resource_group.runtime.name
  allocation_method   = "Static"
  sku                 = "Standard"
  domain_name_label   = local.public_dns_label
  tags                = local.tags
}

resource "azurerm_network_interface" "runtime" {
  name                = "${local.name_prefix}-nic"
  location            = azurerm_resource_group.runtime.location
  resource_group_name = azurerm_resource_group.runtime.name
  tags                = local.tags

  ip_configuration {
    name                          = "platform"
    subnet_id                     = azurerm_subnet.runtime.id
    private_ip_address_allocation = "Static"
    private_ip_address            = "10.42.1.4"
    public_ip_address_id          = azurerm_public_ip.runtime.id
  }
}

resource "azurerm_network_interface_security_group_association" "runtime" {
  network_interface_id      = azurerm_network_interface.runtime.id
  network_security_group_id = azurerm_network_security_group.runtime.id
}
