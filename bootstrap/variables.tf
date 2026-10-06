variable "env" {
  description = "One bootstrap state and AWS account per environment."
  type        = string

  validation {
    condition     = contains(["dev", "staging", "prod", "local"], var.env)
    error_message = "env must be dev, staging, prod, or local."
  }
}

variable "region" {
  type = string
}

variable "github_repo" {
  description = "Trusted GitHub owner/repository, without a URL prefix."
  type        = string

  validation {
    condition     = can(regex("^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$", var.github_repo))
    error_message = "github_repo must be owner/repository without wildcard characters."
  }
}

variable "cluster_name" {
  description = "Existing shared EKS cluster; bootstrap does not create it."
  type        = string
}

variable "enable_ci_identity" {
  description = "Disable OIDC, CI roles, account PAB and cost tag activation for the emulator."
  type        = bool
  default     = true

  validation {
    condition     = var.env != "local" || !var.enable_ci_identity
    error_message = "The local emulator must set enable_ci_identity = false."
  }
}

variable "aws_emulator" {
  description = "Demo only (envs/local): talk to an AWS emulator via AWS_ENDPOINT_URL with dummy credentials."
  type        = bool
  default     = false
}
