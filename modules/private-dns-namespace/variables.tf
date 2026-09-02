variable "name" {
  description = "DNS name of the namespace, e.g. code-intelligence.internal. Resolvable only from inside the VPC."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9.-]{0,251}[a-z0-9]$", var.name))
    error_message = "name must be a DNS name: lowercase alphanumeric labels with hyphens, separated by dots."
  }
}

variable "vpc_id" {
  description = "VPC the namespace is associated with. Only resolvers inside this VPC see the names."
  type        = string
}

variable "description" {
  description = "Description on the namespace. Null leaves it unset."
  type        = string
  default     = null
}

variable "services" {
  description = "Service names to register in the namespace, e.g. [\"api\", \"query\"]. Each becomes <service>.<name>, answering with a multivalue A record per healthy task ENI. Pass the matching service_registry_arns entry to ecs-service's service_registry_arn so ECS registers task addresses."
  type        = set(string)
  default     = []

  validation {
    condition     = alltrue([for s in var.services : can(regex("^[a-z][a-z0-9-]{0,62}$", s))])
    error_message = "Every service must be a single lowercase DNS label: alphanumeric with hyphens, starting with a letter, at most 63 characters."
  }
}
