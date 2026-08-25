variable "name" {
  description = "Cluster name, e.g. impel-gateway-dev."
  type        = string

  validation {
    condition     = can(regex("^[a-zA-Z0-9_-]{1,255}$", var.name))
    error_message = "name must be alphanumeric with hyphens or underscores, max 255 characters."
  }
}

variable "capacity_providers" {
  description = "Capacity providers available to services in this cluster. Prod SEA offers FARGATE and FARGATE_SPOT."
  type        = list(string)
  default     = ["FARGATE", "FARGATE_SPOT"]

  validation {
    condition     = length(var.capacity_providers) > 0
    error_message = "At least one capacity provider is required."
  }
}

variable "default_capacity_provider_strategy" {
  description = "Strategy applied to services that do not specify their own. Empty matches prod SEA, where every service declares its own strategy."
  type = list(object({
    capacity_provider = string
    weight            = optional(number, 1)
    base              = optional(number, 0)
  }))
  default = []
}

variable "enable_container_insights" {
  description = "Enable CloudWatch Container Insights. On in prod SEA."
  type        = bool
  default     = true
}
