variable "aws_region" {
  description = "AWS Region that stores the Terraform state bucket."
  type        = string
  default     = "eu-central-1"
}

variable "project_name" {
  description = "Stable name used to identify the state bucket and its tags."
  type        = string
  default     = "event-sourced-cqrs"

  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.project_name))
    error_message = "project_name must contain only lowercase letters, digits, and hyphens."
  }
}
