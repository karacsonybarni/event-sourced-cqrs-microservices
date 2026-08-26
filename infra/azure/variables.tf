variable "subscription_id" {
  description = "Azure subscription that owns the runtime resources."
  type        = string

  validation {
    condition     = can(regex("^[0-9a-fA-F-]{36}$", var.subscription_id))
    error_message = "subscription_id must be an Azure subscription UUID."
  }
}

variable "tenant_id" {
  description = "Microsoft Entra tenant that owns the GitHub deployment identity."
  type        = string

  validation {
    condition     = can(regex("^[0-9a-fA-F-]{36}$", var.tenant_id))
    error_message = "tenant_id must be a Microsoft Entra tenant UUID."
  }
}

variable "azure_location" {
  description = "Azure region for all runtime resources."
  type        = string
  default     = "polandcentral"
}

variable "project_name" {
  description = "Stable resource-name and tagging prefix."
  type        = string
  default     = "event-sourced-cqrs"

  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.project_name))
    error_message = "project_name must contain only lowercase letters, digits, and hyphens."
  }
}

variable "environment" {
  description = "Deployment environment recorded on cloud resources."
  type        = string
  default     = "cloud"
}

variable "vm_size" {
  description = "Credit-backed x86 VM shape with the measured eight-GiB capacity required by the complete topology."
  type        = string
  default     = "Standard_B2as_v2"

  validation {
    condition     = var.vm_size == "Standard_B2as_v2"
    error_message = "vm_size must use the tested two-vCPU/eight-GiB x86 shape."
  }
}

variable "os_disk_size_gib" {
  description = "Encrypted OS disk size for images, databases, Kafka, and build artifacts."
  type        = number
  default     = 64

  validation {
    condition     = var.os_disk_size_gib >= 32 && var.os_disk_size_gib <= 128
    error_message = "os_disk_size_gib must be between 32 and 128 GiB."
  }
}

variable "admin_username" {
  description = "Non-root administrative account created by Azure."
  type        = string
  default     = "azuredeploy"
}

variable "admin_ssh_public_key" {
  description = "Recovery-only SSH public key; the network security group does not expose SSH."
  type        = string
  sensitive   = true

  validation {
    condition     = can(regex("^ssh-(ed25519|rsa)[[:space:]]", var.admin_ssh_public_key))
    error_message = "admin_ssh_public_key must be an OpenSSH public key."
  }
}

variable "repository_url" {
  description = "Public Git repository cloned by the managed deployment host."
  type        = string
  default     = "https://github.com/karacsonybarni/event-sourced-cqrs-microservices.git"
}

variable "repository_ref" {
  description = "Initial Git revision deployed during VM bootstrap."
  type        = string
  default     = "main"
}

variable "github_repository" {
  description = "GitHub owner/repository allowed to deploy to the Azure VM."
  type        = string
  default     = "karacsonybarni/event-sourced-cqrs-microservices"

  validation {
    condition     = can(regex("^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$", var.github_repository))
    error_message = "github_repository must use the owner/repository format."
  }
}

variable "github_repository_owner_id" {
  description = "Immutable GitHub numeric owner ID included in the OIDC subject."
  type        = string

  validation {
    condition     = can(regex("^[0-9]+$", var.github_repository_owner_id))
    error_message = "github_repository_owner_id must be a numeric GitHub account ID."
  }
}

variable "github_repository_id" {
  description = "Immutable GitHub numeric repository ID included in the OIDC subject."
  type        = string

  validation {
    condition     = can(regex("^[0-9]+$", var.github_repository_id))
    error_message = "github_repository_id must be a numeric GitHub repository ID."
  }
}

variable "github_environment" {
  description = "GitHub environment whose immutable OIDC subject can deploy to Azure."
  type        = string
  default     = "cloud"
}

variable "acme_email" {
  description = "Contact address used by the ACME certificate issuer."
  type        = string
  default     = "karacsony.barni@gmail.com"

  validation {
    condition     = can(regex("^[^@[:space:]]+@[^@[:space:]]+\\.[^@[:space:]]+$", var.acme_email))
    error_message = "acme_email must be a valid email address."
  }
}

variable "compose_version" {
  description = "Pinned Docker Compose plugin version installed during bootstrap."
  type        = string
  default     = "v5.5.0"

  validation {
    condition     = can(regex("^v[0-9]+\\.[0-9]+\\.[0-9]+$", var.compose_version))
    error_message = "compose_version must be a complete vMAJOR.MINOR.PATCH release."
  }
}

variable "buildx_version" {
  description = "Pinned Docker Buildx plugin version required by Docker Compose builds."
  type        = string
  default     = "v0.36.1"

  validation {
    condition     = can(regex("^v[0-9]+\\.[0-9]+\\.[0-9]+$", var.buildx_version))
    error_message = "buildx_version must be a complete vMAJOR.MINOR.PATCH release."
  }
}

variable "buildx_sha256" {
  description = "SHA-256 digest of the pinned Linux AMD64 Docker Buildx binary."
  type        = string
  default     = "48af8a397ebd60178778bf63611dbcebe5f5e7a9be90eb9147b24b9587455778"

  validation {
    condition     = can(regex("^[a-f0-9]{64}$", var.buildx_sha256))
    error_message = "buildx_sha256 must be a lowercase SHA-256 digest."
  }
}

variable "monthly_budget_usd" {
  description = "Monthly cost budget used as an explicit cost-control signal."
  type        = number
  default     = 25

  validation {
    condition     = var.monthly_budget_usd >= 1
    error_message = "monthly_budget_usd must be at least 1 USD."
  }
}

variable "budget_alert_email" {
  description = "Optional address for budget notifications."
  type        = string
  default     = null
  nullable    = true

  validation {
    condition     = var.budget_alert_email == null || can(regex("^[^@[:space:]]+@[^@[:space:]]+\\.[^@[:space:]]+$", var.budget_alert_email))
    error_message = "budget_alert_email must be null or a valid email address."
  }
}
