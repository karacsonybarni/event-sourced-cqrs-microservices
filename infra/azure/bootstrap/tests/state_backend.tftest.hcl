mock_provider "azurerm" {
  override_data {
    target = data.azurerm_client_config.current
    values = {
      object_id = "00000000-0000-0000-0000-000000000001"
    }
  }
}

run "secure_state_backend" {
  command = plan

  variables {
    subscription_id = "00000000-0000-0000-0000-000000000000"
    state_access_ip = "203.0.113.10"
  }

  assert {
    condition     = azurerm_storage_container.terraform_state.container_access_type == "private"
    error_message = "Terraform state must never be publicly reachable."
  }

  assert {
    condition     = azurerm_storage_account.terraform_state.blob_properties[0].versioning_enabled
    error_message = "Terraform state must retain versions for recovery."
  }

  assert {
    condition     = !azurerm_storage_account.terraform_state.shared_access_key_enabled
    error_message = "Terraform state must use Microsoft Entra authentication instead of storage keys."
  }
  assert {
    condition     = azurerm_storage_account.terraform_state.network_rules[0].default_action == "Deny"
    error_message = "Terraform state must reject data-plane access outside the trusted operator address."
  }
}
