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
    error_message = "The runtime VM must retain the tested two-vCPU/eight-GiB capacity."
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
    error_message = "The deployment host must retain enough disk space for builds and stateful containers."
  }

  assert {
    condition     = azurerm_network_security_rule.http.destination_port_range == "80" && azurerm_network_security_rule.https.destination_port_range == "443"
    error_message = "Only the Caddy HTTP and HTTPS entry points may be publicly exposed."
  }

  assert {
    condition     = local.github_oidc_subject == "repo:karacsonybarni@14146083/event-sourced-cqrs-microservices@1343825530:environment:cloud"
    error_message = "Microsoft Entra must trust only the immutable repository identity and cloud environment."
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
    condition     = azurerm_consumption_budget_resource_group.runtime.amount == 25
    error_message = "The deployment must retain a low monthly cost signal."
  }
}
