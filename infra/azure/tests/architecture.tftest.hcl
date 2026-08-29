mock_provider "azurerm" {
  override_data {
    target = data.azurerm_client_config.current
    values = {
      object_id       = "00000000-0000-0000-0000-000000000001"
      subscription_id = "00000000-0000-0000-0000-000000000000"
      tenant_id       = "00000000-0000-0000-0000-000000000002"
    }
  }

  override_resource {
    target          = azurerm_public_ip.runtime
    override_during = plan
    values = {
      fqdn = "escqrs-0000000000.polandcentral.cloudapp.azure.com"
    }
  }

  override_resource {
    target          = azurerm_subnet.functions
    override_during = plan
    values = {
      id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/event-sourced-cqrs-cloud/providers/Microsoft.Network/virtualNetworks/event-sourced-cqrs-cloud-vnet/subnets/serverless"
    }
  }

  override_resource {
    target          = azurerm_subnet.private_endpoints
    override_during = plan
    values = {
      id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/event-sourced-cqrs-cloud/providers/Microsoft.Network/virtualNetworks/event-sourced-cqrs-cloud-vnet/subnets/private-endpoints"
    }
  }
}

mock_provider "azuread" {
  override_data {
    target = data.azuread_client_config.current
    values = {
      object_id = "00000000-0000-0000-0000-000000000001"
      tenant_id = "00000000-0000-0000-0000-000000000002"
    }
  }
}

run "cost_controlled_cloud_topology" {
  command = plan

  variables {
    subscription_id            = "00000000-0000-0000-0000-000000000000"
    tenant_id                  = "00000000-0000-0000-0000-000000000002"
    admin_ssh_public_key       = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAICpQutGdvsI9RhoiHyobTD/0dNDey+Rn6p1/HBGvzMBO terraform-test"
    github_repository_owner_id = "14146083"
    github_repository_id       = "1343825530"
  }

  assert {
    condition     = azurerm_linux_virtual_machine.runtime.size == "Standard_B2as_v2"
    error_message = "The runtime VM must retain the tested two-vCPU/eight-GiB K3s and platform capacity."
  }

  assert {
    condition     = azurerm_linux_virtual_machine.runtime.disable_password_authentication
    error_message = "The deployment host must reject password authentication."
  }

  assert {
    condition     = azurerm_linux_virtual_machine.runtime.secure_boot_enabled && azurerm_linux_virtual_machine.runtime.vtpm_enabled
    error_message = "The deployment host must use trusted launch protections."
  }

  assert {
    condition     = azurerm_linux_virtual_machine.runtime.os_disk[0].disk_size_gb == 64
    error_message = "The deployment host must retain enough disk space for builds, K3s, images, and stateful platform containers."
  }

  assert {
    condition     = azurerm_network_security_rule.http.destination_port_range == "80" && azurerm_network_security_rule.https.destination_port_range == "443"
    error_message = "Only the Caddy HTTP and HTTPS entry points may be publicly exposed."
  }

  assert {
    condition = (
      azurerm_network_security_rule.function_kafka.direction == "Inbound" &&
      azurerm_network_security_rule.function_kafka.access == "Allow" &&
      azurerm_network_security_rule.function_kafka.protocol == "Tcp" &&
      azurerm_network_security_rule.function_kafka.source_address_prefix == azurerm_subnet.functions.address_prefixes[0] &&
      azurerm_network_security_rule.function_kafka.destination_address_prefix == "10.42.1.4" &&
      azurerm_network_security_rule.function_kafka.destination_port_range == "9094"
    )
    error_message = "The Function subnet must explicitly allow the VM Kafka VNET listener on 10.42.1.4:9094."
  }

  assert {
    condition     = local.github_oidc_subject == "repo:karacsonybarni@14146083/event-sourced-cqrs-microservices@1343825530:environment:cloud"
    error_message = "Microsoft Entra must trust only the immutable repository identity and cloud environment."
  }

  assert {
    condition     = output.public_api_url == "https://escqrs-0000000000.polandcentral.cloudapp.azure.com"
    error_message = "The public API URL must be canonical and omit a trailing slash before callers append paths."
  }

  assert {
    condition     = strcontains(base64decode(azurerm_linux_virtual_machine.runtime.custom_data), "Environment=HOME=/root")
    error_message = "The systemd deployment service must provide the home directory required by Maven Wrapper."
  }

  assert {
    condition     = strcontains(base64decode(azurerm_linux_virtual_machine.runtime.custom_data), "openjdk-21-jdk-headless") && strcontains(base64decode(azurerm_linux_virtual_machine.runtime.custom_data), "javac -version")
    error_message = "The deployment host must include and verify the Java compiler used by the Maven build."
  }

  assert {
    condition     = strcontains(base64decode(azurerm_linux_virtual_machine.runtime.custom_data), "systemctl enable event-sourced-cqrs.service") && !strcontains(base64decode(azurerm_linux_virtual_machine.runtime.custom_data), "systemctl enable --now event-sourced-cqrs.service")
    error_message = "Cloud-init must defer the first application start until provisioning injects the runtime endpoints."
  }

  assert {
    condition     = azurerm_consumption_budget_resource_group.runtime.amount == 25
    error_message = "The deployment must retain a low monthly cost signal."
  }

  assert {
    condition     = azurerm_cosmosdb_account.activity.free_tier_enabled && azurerm_cosmosdb_sql_database.activity.throughput == 400
    error_message = "The NoSQL projection must remain inside the Cosmos DB lifetime free-tier allowance."
  }

  assert {
    condition = (
      azurerm_function_app_flex_consumption.activity.maximum_instance_count == 2 &&
      length(azurerm_function_app_flex_consumption.activity.always_ready) == 1 &&
      one(azurerm_function_app_flex_consumption.activity.always_ready).name == "function:projectOrderActivity" &&
      one(azurerm_function_app_flex_consumption.activity.always_ready).instance_count == 1
    )
    error_message = "The Function must keep only the Kafka projection always ready and cap burst scale at two instances."
  }

  assert {
    condition     = azurerm_function_app_flex_consumption.activity.virtual_network_subnet_id == azurerm_subnet.functions.id
    error_message = "The Function must reach Kafka only through the delegated private-network subnet."
  }

  assert {
    condition     = azurerm_function_app_flex_consumption.activity.https_only
    error_message = "The public Function endpoint must reject cleartext HTTP requests."
  }

  assert {
    condition     = azurerm_storage_account.activity_function.shared_access_key_enabled == false && azurerm_cosmosdb_account.activity.local_authentication_enabled == false
    error_message = "The serverless projection must use managed identities instead of storage or Cosmos DB account keys."
  }

  assert {
    condition     = azurerm_storage_account.activity_function.network_rules[0].default_action == "Deny"
    error_message = "Function storage must deny traffic outside its explicit network boundary."
  }

  assert {
    condition     = length(azurerm_private_endpoint.activity_storage) == 3
    error_message = "Function storage must expose blob, queue, and table services only through private endpoints."
  }
}
