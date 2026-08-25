variable "aws_region" {
  description = "AWS Region for all runtime resources."
  type        = string
  default     = "eu-central-1"
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

variable "instance_type" {
  description = "Free-plan-eligible eight-GiB x86 instance used for the complete single-node platform."
  type        = string
  default     = "m7i-flex.large"

  validation {
    condition     = var.instance_type == "m7i-flex.large"
    error_message = "instance_type must use the tested Free-plan-eligible x86 two-vCPU/eight-GiB shape."
  }
}

variable "root_volume_size_gib" {
  description = "Encrypted root volume size for images, databases, Kafka, and build artifacts."
  type        = number
  default     = 40

  validation {
    condition     = var.root_volume_size_gib >= 30 && var.root_volume_size_gib <= 100
    error_message = "root_volume_size_gib must be between 30 and 100 GiB."
  }
}

variable "repository_url" {
  description = "Public Git repository cloned by the managed deployment host."
  type        = string
  default     = "https://github.com/karacsonybarni/event-sourced-cqrs-microservices.git"
}

variable "repository_ref" {
  description = "Initial Git revision deployed during instance bootstrap."
  type        = string
  default     = "main"
}

variable "github_repository" {
  description = "GitHub owner/repository allowed to assume the AWS deployment role."
  type        = string
  default     = "karacsonybarni/event-sourced-cqrs-microservices"

  validation {
    condition     = can(regex("^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$", var.github_repository))
    error_message = "github_repository must use the owner/repository format."
  }
}

variable "github_repository_owner_id" {
  description = "Immutable GitHub numeric owner ID included in the repository OIDC subject."
  type        = string

  validation {
    condition     = can(regex("^[0-9]+$", var.github_repository_owner_id))
    error_message = "github_repository_owner_id must be a numeric GitHub account ID."
  }
}

variable "github_repository_id" {
  description = "Immutable GitHub numeric repository ID included in the repository OIDC subject."
  type        = string

  validation {
    condition     = can(regex("^[0-9]+$", var.github_repository_id))
    error_message = "github_repository_id must be a numeric GitHub repository ID."
  }
}

variable "github_environment" {
  description = "GitHub environment whose OIDC subject can deploy through Systems Manager."
  type        = string
  default     = "cloud"
}

variable "github_oidc_provider_arn" {
  description = "Existing GitHub OIDC provider ARN; leave null to create one in this account."
  type        = string
  default     = null
  nullable    = true
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
  description = "Optional address for 50%, 80%, and forecast budget notifications."
  type        = string
  default     = null
  nullable    = true

  validation {
    condition     = var.budget_alert_email == null || can(regex("^[^@[:space:]]+@[^@[:space:]]+\\.[^@[:space:]]+$", var.budget_alert_email))
    error_message = "budget_alert_email must be null or a valid email address."
  }
}
