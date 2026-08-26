data "azurerm_client_config" "current" {}

locals {
  subscription_suffix = substr(replace(var.subscription_id, "-", ""), 0, 10)
  name_prefix         = "${var.project_name}-${var.environment}"
  public_dns_label    = "escqrs-${local.subscription_suffix}"
  github_owner        = split("/", var.github_repository)[0]
  github_name         = split("/", var.github_repository)[1]
  github_oidc_subject = "repo:${local.github_owner}@${var.github_repository_owner_id}/${local.github_name}@${var.github_repository_id}:environment:${var.github_environment}"
  tags = {
    Environment = var.environment
    ManagedBy   = "Terraform"
    Project     = var.project_name
  }
}

resource "azurerm_resource_group" "runtime" {
  name     = local.name_prefix
  location = var.azure_location
  tags     = local.tags
}
