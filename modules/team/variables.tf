variable "env" {
  type = string
  validation {
    condition     = contains(["dev", "staging", "prod", "local"], var.env)
    error_message = "Environment must be dev, staging, prod or local."
  }
}

variable "team" {
  type = string
  validation {
    condition     = can(regex("^[a-z][a-z0-9]{1,19}$", var.team))
    error_message = "Team must be 2–20 lowercase letters/digits, starting with a letter."
  }
}

variable "owner" {
  type = object({
    github_team = string
    contact     = string
    cost_center = string
  })
}

variable "workload" {
  type = object({
    namespace       = string
    service_account = string
  })

  validation {
    condition     = var.workload.namespace == var.team || startswith(var.workload.namespace, "${var.team}-")
    error_message = "Workload namespace must equal the team or start with <team>-."
  }
}

variable "buckets" {
  type = list(object({
    name       = string
    visibility = optional(string)
    public = optional(object({
      mode          = optional(string)
      justification = optional(string)
    }))
    lifecycle = optional(string, "active")
  }))

  validation {
    condition     = alltrue([for b in var.buckets : contains(["private", "public"], coalesce(b.visibility, "missing"))])
    error_message = "Every bucket requires visibility: private or public; there is no default."
  }

  validation {
    condition = alltrue([for b in var.buckets : b.visibility == "public" ? try(
      contains(["cloudfront", "direct"], b.public.mode) && trimspace(b.public.justification) != "", false
    ) : b.public == null])
    error_message = "Public buckets require mode cloudfront or direct and a nonempty justification; private buckets forbid public settings."
  }

  validation {
    condition = length(distinct([for b in var.buckets : b.name])) == length(var.buckets) && alltrue([
      for b in var.buckets : can(regex("^[a-z0-9]([a-z0-9-]{0,22}[a-z0-9])?$", b.name)) && !strcontains(b.name, "--")
    ])
    error_message = "Bucket names must be unique, 1–24 lowercase letters/digits/single hyphens with alphanumeric ends."
  }


  validation {
    condition = length(var.buckets) <= 20 && (
      var.lifecycle_state == "decommission" || anytrue([for b in var.buckets : b.lifecycle == "active"])
    )
    error_message = "A team may have at most 20 buckets and needs an active bucket unless decommissioning."
  }

  validation {
    condition     = alltrue([for b in var.buckets : contains(["active", "decommission"], b.lifecycle)])
    error_message = "Bucket lifecycle must be active or decommission."
  }
}

variable "lifecycle_state" {
  type     = string
  default  = "active"
  nullable = false
  validation {
    condition     = contains(["active", "decommission"], var.lifecycle_state)
    error_message = "Team lifecycle must be active or decommission."
  }
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
