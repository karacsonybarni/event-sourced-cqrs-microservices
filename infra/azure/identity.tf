data "azuread_client_config" "current" {}

resource "azuread_application" "github_deploy" {
  display_name = "${local.name_prefix}-github-deploy"
  owners       = [data.azuread_client_config.current.object_id]
}

resource "azuread_service_principal" "github_deploy" {
  client_id = azuread_application.github_deploy.client_id
  owners    = [data.azuread_client_config.current.object_id]
}

resource "azuread_application_federated_identity_credential" "github_deploy" {
  application_id = azuread_application.github_deploy.id
  display_name   = "github-${var.github_environment}"
  description    = "Immutable GitHub repository identity for the ${var.github_environment} environment"
  audiences      = ["api://AzureADTokenExchange"]
  issuer         = "https://token.actions.githubusercontent.com"
  subject        = local.github_oidc_subject
}

resource "azurerm_role_definition" "github_deploy" {
  name        = "${local.name_prefix}-vm-deployer-${local.subscription_suffix}"
  scope       = azurerm_resource_group.runtime.id
  description = "Read the deployment VM and invoke Azure Run Command."

  permissions {
    actions = [
      "Microsoft.Compute/virtualMachines/read",
      "Microsoft.Compute/virtualMachines/runCommand/action",
      "Microsoft.Resources/subscriptions/resourceGroups/read",
    ]
    not_actions = []
  }

  assignable_scopes = [azurerm_resource_group.runtime.id]
}

resource "azurerm_role_assignment" "github_deploy" {
  scope                            = azurerm_resource_group.runtime.id
  role_definition_id               = azurerm_role_definition.github_deploy.role_definition_resource_id
  principal_id                     = azuread_service_principal.github_deploy.object_id
  skip_service_principal_aad_check = true
}
