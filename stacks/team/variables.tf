variable "team" {
  type = string
  validation {
    condition     = can(regex("^[a-z][a-z0-9]{1,19}$", var.team))
    error_message = "Team must be 2–20 lowercase letters/digits, starting with a letter."
  }
}

variable "env" {
  type = string
  validation {
    condition     = contains(["dev", "staging", "prod", "local"], var.env)
    error_message = "Environment must be dev, staging, prod or local."
  }
}

variable "config_file" {
  type = string

  # Same checks as the module, repeated here so tofu test can test them.
  validation {
    condition     = alltrue([for b in yamldecode(file(var.config_file)).buckets : contains(["private", "public"], coalesce(try(b.visibility, null), "missing"))])
    error_message = "Every bucket requires visibility: private or public; there is no default."
  }

  validation {
    condition = alltrue([for b in yamldecode(file(var.config_file)).buckets : try(b.visibility, null) == "public" ? try(
      contains(["cloudfront", "direct"], b.public.mode) && trimspace(b.public.justification) != "", false
    ) : try(b.public, null) == null])
    error_message = "Public buckets require mode cloudfront or direct and a nonempty justification; private buckets forbid public settings."
  }

  validation {
    condition = length(distinct([for b in yamldecode(file(var.config_file)).buckets : b.name])) == length(yamldecode(file(var.config_file)).buckets) && alltrue([
      for b in yamldecode(file(var.config_file)).buckets : can(regex("^[a-z0-9]([a-z0-9-]{0,22}[a-z0-9])?$", b.name)) && !strcontains(b.name, "--")
    ])
    error_message = "Bucket names must be unique, 1–24 lowercase letters/digits/single hyphens with alphanumeric ends."
  }


  validation {
    condition = length(yamldecode(file(var.config_file)).buckets) <= 20 && (
      try(yamldecode(file(var.config_file)).lifecycle, "active") == "decommission" || anytrue([for b in yamldecode(file(var.config_file)).buckets : try(b.lifecycle, "active") == "active"])
    )
    error_message = "A team may have at most 20 buckets and needs an active bucket unless decommissioning."
  }

  validation {
    condition     = yamldecode(file(var.config_file)).workload.namespace == var.team || startswith(yamldecode(file(var.config_file)).workload.namespace, "${var.team}-")
    error_message = "Workload namespace must equal the team or start with <team>-."
  }
}

variable "region" {
  type = string
}

variable "cluster_name" {
  type = string
}

variable "permissions_boundary_arn" {
  type = string
}

variable "enable_pod_identity" {
  type    = bool
  default = true
}

variable "enable_cloudfront" {
  type    = bool
  default = true
}

variable "aws_emulator" {
  description = "Demo only (envs/local): talk to an AWS emulator via AWS_ENDPOINT_URL with dummy credentials."
  type        = bool
  default     = false
}
