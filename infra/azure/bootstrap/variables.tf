variable "subscription_id" {
  description = "Azure subscription that owns the Terraform state backend."
  type        = string

  validation {
    condition     = can(regex("^[0-9a-fA-F-]{36}$", var.subscription_id))
    error_message = "subscription_id must be an Azure subscription UUID."
  }
}

variable "location" {
  description = "Azure region for the Terraform state backend."
  type        = string
  default     = "polandcentral"
}

variable "project_name" {
  description = "Stable resource-name and tagging prefix."
  type        = string
  default     = "event-sourced-cqrs"
}

variable "state_access_ip" {
  description = "Single trusted public IPv4 address allowed to access the Terraform state data plane."
  type        = string

  validation {
    condition     = can(cidrhost("${var.state_access_ip}/32", 0)) && can(regex("^[0-9]+\\.[0-9]+\\.[0-9]+\\.[0-9]+$", var.state_access_ip))
    error_message = "state_access_ip must be a single IPv4 address without a CIDR suffix."
  }
}
