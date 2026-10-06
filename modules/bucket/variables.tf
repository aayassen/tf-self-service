variable "env" {
  type = string
}

variable "team" {
  type = string
}

variable "name" {
  type = string

  validation {
    condition     = can(regex("^[a-z0-9]([a-z0-9-]{0,22}[a-z0-9])?$", var.name)) && !strcontains(var.name, "--")
    error_message = "Bucket name must be 1–24 lowercase letters, digits or single hyphens, with alphanumeric ends."
  }

}

variable "visibility" {
  type     = string
  nullable = true
  # Null so a missing value hits the validation below (there is no default).
  default = null

  validation {
    condition     = contains(["private", "public"], coalesce(var.visibility, "missing"))
    error_message = "Visibility is required and must be private or public."
  }
}

variable "public" {
  type = object({
    mode          = optional(string)
    justification = optional(string)
  })
  default = null

  validation {
    condition = var.visibility == "public" ? try(
      contains(["cloudfront", "direct"], var.public.mode) && trimspace(var.public.justification) != "", false
    ) : var.public == null
    error_message = "Public buckets require mode cloudfront or direct and a nonempty justification; private buckets forbid public settings."
  }
}

variable "lifecycle_state" {
  type     = string
  default  = "active"
  nullable = false

  validation {
    condition     = contains(["active", "decommission"], var.lifecycle_state)
    error_message = "Lifecycle must be active or decommission."
  }
}

variable "enable_cloudfront" {
  type    = bool
  default = true
}
