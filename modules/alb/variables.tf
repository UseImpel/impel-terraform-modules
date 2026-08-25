variable "name" {
  description = "Load balancer name, e.g. impel-gateway-dev. Also prefixes the security group and access log bucket."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{1,30}$", var.name))
    error_message = "name must be lowercase alphanumeric with hyphens, start with a letter, and be at most 32 characters — the ELB name limit."
  }
}

variable "vpc_id" {
  description = "VPC the load balancer and its security group live in."
  type        = string
}

variable "subnet_ids" {
  description = "Subnets to attach. Public subnets for an internet-facing ALB, private for an internal one. At least two AZs."
  type        = list(string)

  validation {
    condition     = length(var.subnet_ids) >= 2
    error_message = "An ALB requires subnets in at least two availability zones."
  }
}

variable "internal" {
  description = "True gives the ALB private addresses only. Prod SEA runs internet-facing load balancers; dev runs one internal."
  type        = bool
  default     = false
}

variable "certificate_arn" {
  description = "ACM certificate for the HTTPS listener. Null skips the :443 listener entirely and serves the default action on :80 instead of redirecting."
  type        = string
  default     = null
}

variable "enable_https" {
  description = "Whether to serve HTTPS, stated rather than inferred from certificate_arn. Null infers it, which is correct whenever the certificate already exists. Set it explicitly when the certificate is created in the same apply: its ARN is unknown at plan time, and count and for_each on the listener and its ingress rules cannot be decided from an unknown value."
  type        = bool
  default     = null
}

variable "additional_certificate_arns" {
  description = "Extra certificates attached to the HTTPS listener via SNI."
  type        = list(string)
  default     = []
}

variable "ssl_policy" {
  description = "Predefined TLS policy for the HTTPS listener. Matches prod SEA."
  type        = string
  default     = "ELBSecurityPolicy-TLS13-1-2-2021-06"
}

variable "ingress_cidr_blocks" {
  description = "CIDRs allowed to reach the listeners. Prod SEA allows 0.0.0.0/0; an internal dev ALB should be scoped to the VPC."
  type        = list(string)
  default     = ["0.0.0.0/0"]

  validation {
    condition     = alltrue([for c in var.ingress_cidr_blocks : can(cidrnetmask(c))])
    error_message = "Every ingress_cidr_blocks entry must be a valid IPv4 CIDR."
  }
}

variable "idle_timeout" {
  description = "Seconds an idle connection is held open. Raise it for streaming responses; the gateway proxies long-lived model output."
  type        = number
  default     = 60

  validation {
    condition     = var.idle_timeout >= 1 && var.idle_timeout <= 4000
    error_message = "idle_timeout must be between 1 and 4000 seconds."
  }
}

variable "enable_deletion_protection" {
  description = "Block deletion of the load balancer. On anywhere that serves traffic people depend on."
  type        = bool
  default     = false
}

variable "drop_invalid_header_fields" {
  description = "Drop malformed HTTP headers rather than forwarding them."
  type        = bool
  default     = true
}

variable "enable_access_logs" {
  description = "Write access logs to a bucket this module creates. On in prod SEA; off in dev, where the logs are noise."
  type        = bool
  default     = false
}

variable "access_log_retention_days" {
  description = "Days before access log objects expire. Ignored when enable_access_logs is false."
  type        = number
  default     = 90

  validation {
    condition     = var.access_log_retention_days > 0
    error_message = "access_log_retention_days must be positive."
  }
}

variable "default_fixed_response" {
  description = "Response returned by the HTTPS listener when no rule matches. Requests for an unknown host get this rather than being forwarded anywhere."
  type = object({
    status_code  = optional(number, 404)
    content_type = optional(string, "application/json")
    message_body = optional(string, "{\"error\":\"no route for host\"}")
  })
  default = {}
}
