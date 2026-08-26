output "resource_group_name" {
  description = "Resource group containing the Terraform state backend."
  value       = azurerm_resource_group.terraform_state.name
}

output "storage_account_name" {
  description = "Storage account containing versioned Terraform state."
  value       = azurerm_storage_account.terraform_state.name
}

output "container_name" {
  description = "Private blob container containing Terraform state."
  value       = azurerm_storage_container.terraform_state.name
}
