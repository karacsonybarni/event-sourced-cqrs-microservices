locals {
  activity_function_name  = "escqrs-activity-${local.subscription_suffix}"
  activity_storage_name   = "escqrsfn${local.subscription_suffix}"
  activity_database_name  = "orders-activity"
  activity_container_name = "events"
}

resource "azurerm_user_assigned_identity" "activity_function" {
  name                = "${local.name_prefix}-activity-function"
  location            = azurerm_resource_group.runtime.location
  resource_group_name = azurerm_resource_group.runtime.name
  tags                = local.tags
}

resource "azurerm_storage_account" "activity_function" {
  name                            = local.activity_storage_name
  resource_group_name             = azurerm_resource_group.runtime.name
  location                        = azurerm_resource_group.runtime.location
  account_tier                    = "Standard"
  account_replication_type        = "LRS"
  min_tls_version                 = "TLS1_2"
  allow_nested_items_to_be_public = false
  shared_access_key_enabled       = false
  tags                            = local.tags

  network_rules {
    default_action = "Deny"
    bypass         = ["AzureServices"]
  }
}

resource "azurerm_storage_container" "activity_function_deployments" {
  name                  = "function-releases"
  storage_account_id    = azurerm_storage_account.activity_function.id
  container_access_type = "private"
}

resource "azurerm_private_dns_zone" "activity_storage" {
  for_each = toset(["blob", "queue", "table"])

  name                = "privatelink.${each.value}.core.windows.net"
  resource_group_name = azurerm_resource_group.runtime.name
  tags                = local.tags
}

resource "azurerm_private_dns_zone_virtual_network_link" "activity_storage" {
  for_each = azurerm_private_dns_zone.activity_storage

  name                = "${local.name_prefix}-${each.key}"
  private_dns_zone_id = each.value.id
  virtual_network_id  = azurerm_virtual_network.runtime.id
  tags                = local.tags
}

resource "azurerm_private_endpoint" "activity_storage" {
  for_each = azurerm_private_dns_zone.activity_storage

  name                = "${local.name_prefix}-activity-${each.key}"
  location            = azurerm_resource_group.runtime.location
  resource_group_name = azurerm_resource_group.runtime.name
  subnet_id           = azurerm_subnet.private_endpoints.id
  tags                = local.tags

  private_service_connection {
    name                           = "${local.name_prefix}-activity-${each.key}"
    private_connection_resource_id = azurerm_storage_account.activity_function.id
    subresource_names              = [each.key]
    is_manual_connection           = false
  }

  private_dns_zone_group {
    name                 = "storage"
    private_dns_zone_ids = [each.value.id]
  }
}

resource "azurerm_role_assignment" "activity_function_blob_owner" {
  scope                = azurerm_storage_account.activity_function.id
  role_definition_name = "Storage Blob Data Owner"
  principal_id         = azurerm_user_assigned_identity.activity_function.principal_id
}

resource "azurerm_role_assignment" "activity_function_queue_contributor" {
  scope                = azurerm_storage_account.activity_function.id
  role_definition_name = "Storage Queue Data Contributor"
  principal_id         = azurerm_user_assigned_identity.activity_function.principal_id
}

resource "azurerm_role_assignment" "activity_function_table_contributor" {
  scope                = azurerm_storage_account.activity_function.id
  role_definition_name = "Storage Table Data Contributor"
  principal_id         = azurerm_user_assigned_identity.activity_function.principal_id
}

resource "azurerm_cosmosdb_account" "activity" {
  name                         = local.activity_function_name
  location                     = azurerm_resource_group.runtime.location
  resource_group_name          = azurerm_resource_group.runtime.name
  offer_type                   = "Standard"
  kind                         = "GlobalDocumentDB"
  free_tier_enabled            = true
  local_authentication_enabled = false

  consistency_policy {
    consistency_level = "Session"
  }

  geo_location {
    location          = azurerm_resource_group.runtime.location
    failover_priority = 0
  }

  tags = local.tags
}

resource "azurerm_cosmosdb_sql_database" "activity" {
  name                = local.activity_database_name
  resource_group_name = azurerm_resource_group.runtime.name
  account_name        = azurerm_cosmosdb_account.activity.name
  throughput          = 400
}

resource "azurerm_cosmosdb_sql_container" "activity" {
  name                  = local.activity_container_name
  resource_group_name   = azurerm_resource_group.runtime.name
  account_name          = azurerm_cosmosdb_account.activity.name
  database_name         = azurerm_cosmosdb_sql_database.activity.name
  partition_key_paths   = ["/orderId"]
  partition_key_version = 2
}

resource "azurerm_cosmosdb_sql_role_assignment" "activity_function" {
  resource_group_name = azurerm_resource_group.runtime.name
  account_name        = azurerm_cosmosdb_account.activity.name
  role_definition_id  = "${azurerm_cosmosdb_account.activity.id}/sqlRoleDefinitions/00000000-0000-0000-0000-000000000002"
  principal_id        = azurerm_user_assigned_identity.activity_function.principal_id
  scope               = azurerm_cosmosdb_account.activity.id
}

resource "azurerm_service_plan" "activity_function" {
  name                = "${local.name_prefix}-activity-function"
  resource_group_name = azurerm_resource_group.runtime.name
  location            = azurerm_resource_group.runtime.location
  os_type             = "Linux"
  sku_name            = "FC1"
  tags                = local.tags
}

resource "azurerm_function_app_flex_consumption" "activity" {
  name                = local.activity_function_name
  resource_group_name = azurerm_resource_group.runtime.name
  location            = azurerm_resource_group.runtime.location
  service_plan_id     = azurerm_service_plan.activity_function.id

  storage_container_type                         = "blobContainer"
  storage_container_endpoint                     = "${azurerm_storage_account.activity_function.primary_blob_endpoint}${azurerm_storage_container.activity_function_deployments.name}"
  storage_authentication_type                    = "UserAssignedIdentity"
  storage_user_assigned_identity_id              = azurerm_user_assigned_identity.activity_function.id
  runtime_name                                   = "java"
  runtime_version                                = "21"
  maximum_instance_count                         = 2
  instance_memory_in_mb                          = 2048
  virtual_network_subnet_id                      = azurerm_subnet.functions.id
  https_only                                     = true
  webdeploy_publish_basic_authentication_enabled = false

  always_ready {
    name           = "function:projectOrderActivity"
    instance_count = 1
  }

  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.activity_function.id]
  }

  app_settings = {
    "AzureWebJobsStorage__accountName"  = azurerm_storage_account.activity_function.name
    "AzureWebJobsStorage__credential"   = "managedidentity"
    "AzureWebJobsStorage__clientId"     = azurerm_user_assigned_identity.activity_function.client_id
    "KAFKA_BROKERS"                     = "10.42.1.4:9094"
    "COSMOS_DATABASE_NAME"              = azurerm_cosmosdb_sql_database.activity.name
    "COSMOS_CONTAINER_NAME"             = azurerm_cosmosdb_sql_container.activity.name
    "CosmosConnection__accountEndpoint" = azurerm_cosmosdb_account.activity.endpoint
    "CosmosConnection__clientId"        = azurerm_user_assigned_identity.activity_function.client_id
  }

  site_config {}

  tags = local.tags

  depends_on = [
    azurerm_private_endpoint.activity_storage,
    azurerm_role_assignment.activity_function_blob_owner,
    azurerm_role_assignment.activity_function_queue_contributor,
    azurerm_role_assignment.activity_function_table_contributor,
    azurerm_cosmosdb_sql_role_assignment.activity_function,
  ]
}

resource "azurerm_role_assignment" "github_activity_function_deploy" {
  scope                = azurerm_function_app_flex_consumption.activity.id
  role_definition_name = "Website Contributor"
  principal_id         = azuread_service_principal.github_deploy.object_id
}
