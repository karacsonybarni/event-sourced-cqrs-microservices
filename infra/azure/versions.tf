terraform {
  required_version = "~> 1.15.0"

  required_providers {
    azuread = {
      source  = "hashicorp/azuread"
      version = "3.9.0"
    }
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "5.0.1"
    }
  }

  backend "azurerm" {
    key              = "event-sourced-cqrs/cloud.tfstate"
    use_azuread_auth = true
  }
}

provider "azurerm" {
  features {}
  subscription_id = var.subscription_id
}

provider "azuread" {
  tenant_id = var.tenant_id
}
