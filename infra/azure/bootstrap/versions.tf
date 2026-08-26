terraform {
  required_version = "~> 1.15.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "5.0.1"
    }
  }
}

provider "azurerm" {
  features {}
  subscription_id = var.subscription_id
  resource_providers_to_register = [
    "Microsoft.Authorization",
    "Microsoft.Resources",
    "Microsoft.Storage",
  ]
}
