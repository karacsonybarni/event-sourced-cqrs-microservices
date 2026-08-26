data "azurerm_client_config" "current" {}

locals {
  subscription_suffix  = substr(replace(var.subscription_id, "-", ""), 0, 12)
  storage_account_name = "escqrs${local.subscription_suffix}"
}

resource "azurerm_resource_group" "terraform_state" {
  name     = "${var.project_name}-tfstate"
  location = var.location

  tags = {
    Environment = "cloud"
    ManagedBy   = "Terraform"
    Project     = var.project_name
    Purpose     = "Terraform state"
  }
}

resource "azurerm_storage_account" "terraform_state" {
  name                            = local.storage_account_name
  resource_group_name             = azurerm_resource_group.terraform_state.name
  location                        = azurerm_resource_group.terraform_state.location
  account_tier                    = "Standard"
  account_replication_type        = "LRS"
  min_tls_version                 = "TLS1_2"
  allow_nested_items_to_be_public = false
  shared_access_key_enabled       = false

  blob_properties {
    versioning_enabled = true
  }

  network_rules {
    default_action = "Deny"
    bypass         = ["AzureServices"]
    ip_rules       = [var.state_access_ip]
  }

  tags = azurerm_resource_group.terraform_state.tags
}

resource "azurerm_storage_container" "terraform_state" {
  name                  = "tfstate"
  storage_account_id    = azurerm_storage_account.terraform_state.id
  container_access_type = "private"
}

resource "azurerm_role_assignment" "terraform_state_owner" {
  scope                = azurerm_storage_account.terraform_state.id
  role_definition_name = "Storage Blob Data Owner"
  principal_id         = data.azurerm_client_config.current.object_id
}
