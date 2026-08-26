output "public_api_url" {
  description = "Stable HTTPS entry point terminated by Caddy on the Azure VM."
  value       = "https://${azurerm_public_ip.runtime.fqdn}"
}

output "vm_id" {
  description = "Azure Run Command deployment target."
  value       = azurerm_linux_virtual_machine.runtime.id
}

output "vm_name" {
  description = "Azure Run Command deployment target name."
  value       = azurerm_linux_virtual_machine.runtime.name
}

output "resource_group_name" {
  description = "Resource group containing the runtime platform."
  value       = azurerm_resource_group.runtime.name
}

output "azure_client_id" {
  description = "GitHub OIDC application client ID."
  value       = azuread_application.github_deploy.client_id
}

output "azure_tenant_id" {
  description = "Microsoft Entra tenant used by GitHub OIDC."
  value       = var.tenant_id
}

output "azure_subscription_id" {
  description = "Azure subscription used by GitHub OIDC."
  value       = var.subscription_id
}

output "github_oidc_subject" {
  description = "Immutable GitHub subject trusted by Microsoft Entra."
  value       = local.github_oidc_subject
}
