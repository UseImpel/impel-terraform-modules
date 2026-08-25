# ---------------------------------------------------------------------------
# Identity and placement
# ---------------------------------------------------------------------------

variable "name" {
  description = "Service name, also the task definition family and the base of every child resource, e.g. impel-gateway-dev."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{1,54}$", var.name))
    error_message = "name must be lowercase alphanumeric with hyphens, start with a letter, and be at most 55 characters — leaving room for resource suffixes."
  }
}

variable "cluster_arn" {
  description = "ARN of the ECS cluster to run in."
  type        = string
}

variable "vpc_id" {
  description = "VPC the task security group and target group belong to."
  type        = string
}

variable "subnet_ids" {
  description = "Private subnets for the tasks."
  type        = list(string)

  validation {
    condition     = length(var.subnet_ids) >= 1
    error_message = "At least one subnet is required."
  }
}

# ---------------------------------------------------------------------------
# Container
# ---------------------------------------------------------------------------

variable "container_name" {
  description = "Name of the container inside the task, e.g. gateway. Referenced by the load balancer attachment."
  type        = string
}

variable "container_image" {
  description = "Full image reference. Pin by digest (repo@sha256:...) as prod does, so a redeployed tag cannot silently change what runs."
  type        = string
}

variable "container_port" {
  description = "Port the container listens on. Prod SEA: gateway 8080, next 3000, identity 3902, sessions 8080."
  type        = number

  validation {
    condition     = var.container_port > 0 && var.container_port <= 65535
    error_message = "container_port must be between 1 and 65535."
  }
}

variable "cpu" {
  description = "Task CPU units. Fargate accepts 256, 512, 1024, 2048, 4096, 8192 and 16384."
  type        = number
  default     = 512

  validation {
    condition     = contains([256, 512, 1024, 2048, 4096, 8192, 16384], var.cpu)
    error_message = "cpu must be one of 256, 512, 1024, 2048, 4096, 8192 or 16384."
  }
}

variable "memory" {
  description = "Task memory in MiB. Must be a valid pairing for the chosen cpu."
  type        = number
  default     = 1024

  validation {
    condition     = var.memory >= 512 && var.memory <= 122880
    error_message = "memory must be between 512 and 122880 MiB."
  }
}

variable "environment_variables" {
  description = "Plain environment variables. Anything sensitive belongs in container_secrets: values here are visible to anyone who can describe the task definition."
  type        = map(string)
  default     = {}
}

variable "container_secrets" {
  description = "Environment variable name to Secrets Manager or SSM reference. Use the secret-arn:KEY:: form to pull one key out of a JSON secret, as prod does."
  type        = map(string)
  default     = {}
}

variable "command" {
  description = "Override the image's CMD. Empty uses the image default."
  type        = list(string)
  default     = []
}

variable "entrypoint" {
  description = "Override the image's ENTRYPOINT. Empty uses the image default."
  type        = list(string)
  default     = []
}

variable "health_check_command" {
  description = "Container-level healthcheck, as a CMD or CMD-SHELL list. Empty omits it and leaves health to the target group. Prod runs one on next and identity only."
  type        = list(string)
  default     = []
}

variable "health_check_interval" {
  description = "Seconds between container healthchecks."
  type        = number
  default     = 30
}

variable "health_check_timeout" {
  description = "Seconds a container healthcheck may take before counting as failed."
  type        = number
  default     = 5
}

variable "health_check_retries" {
  description = "Consecutive container healthcheck failures before the container is unhealthy."
  type        = number
  default     = 3
}

variable "health_check_start_period" {
  description = "Grace seconds before container healthcheck failures are counted."
  type        = number
  default     = 60
}

variable "ephemeral_storage_gib" {
  description = "Task ephemeral storage. Zero uses the 20 GiB Fargate default; prod's next service asks for 30."
  type        = number
  default     = 0

  validation {
    condition     = var.ephemeral_storage_gib == 0 || (var.ephemeral_storage_gib >= 21 && var.ephemeral_storage_gib <= 200)
    error_message = "ephemeral_storage_gib must be 0, or between 21 and 200."
  }
}

# ---------------------------------------------------------------------------
# Service
# ---------------------------------------------------------------------------

variable "desired_count" {
  description = "Task count at creation. Autoscaling takes over afterwards, so changes here are ignored on later applies."
  type        = number
  default     = 2

  validation {
    condition     = var.desired_count >= 0
    error_message = "desired_count cannot be negative."
  }
}

variable "capacity_provider" {
  description = "Capacity provider for the service. FARGATE_SPOT is cheaper but interruptible."
  type        = string
  default     = "FARGATE"

  validation {
    condition     = contains(["FARGATE", "FARGATE_SPOT"], var.capacity_provider)
    error_message = "capacity_provider must be FARGATE or FARGATE_SPOT."
  }
}

variable "platform_version" {
  description = "Fargate platform version. Prod pins 1.4.0 on three services and uses LATEST on sessions."
  type        = string
  default     = "LATEST"
}

variable "health_check_grace_period" {
  description = "Seconds before load balancer health checks can kill a new task. Prod SEA: gateway 600, next 180, identity 120, sessions 180."
  type        = number
  default     = 180
}

variable "enable_execute_command" {
  description = "Allow aws ecs execute-command into running tasks. Off in prod; useful in dev for debugging."
  type        = bool
  default     = false
}

variable "continuous_deployment" {
  description = "Let the service's own application repository roll new images. When true, Terraform stops reconciling which task definition revision the service runs, so an `aws ecs update-service` from a merge pipeline survives the next apply. Terraform still owns the task definition it renders — container_image remains the revision applied when the service is created or when the definition otherwise changes. Leave false to keep the digest in this repository authoritative."
  type        = bool
  default     = false
}

variable "log_retention_days" {
  description = "Retention for the service log group. Prod SEA keeps 90 days."
  type        = number
  default     = 30

  validation {
    condition     = contains([1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1096, 1827, 2192, 2557, 2922, 3288, 3653], var.log_retention_days)
    error_message = "log_retention_days must be a retention period CloudWatch Logs accepts."
  }
}

variable "log_group_name" {
  description = "Override the log group name. Null derives /ecs/<name>/service, matching prod."
  type        = string
  default     = null
}

# ---------------------------------------------------------------------------
# Load balancer
# ---------------------------------------------------------------------------

variable "attach_load_balancer" {
  description = "Put this service behind a load balancer, creating a target group, a listener rule and ALB ingress on the task security group. Must be a literal the caller sets, not derived from another resource: it drives count and has to resolve at plan time, whereas listener_arn is unknown until the load balancer exists."
  type        = bool
  default     = true
}

variable "listener_arn" {
  description = "Listener to attach the forwarding rule to. Required when attach_load_balancer is true."
  type        = string
  default     = null
}

variable "load_balancer_security_group_id" {
  description = "Security group of the load balancer. The task security group accepts the container port from this and nothing else. Required when listener_arn is set."
  type        = string
  default     = null
}

variable "health_check_path" {
  description = "Target group health check path. Prod SEA: gateway /health, next /api/ready, identity /v1/health, sessions /v1/ready."
  type        = string
  default     = "/health"
}

variable "health_check_matcher" {
  description = "HTTP codes counted as healthy."
  type        = string
  default     = "200-299"
}

variable "target_group_health_check" {
  description = "Target group health check timing. Prod SEA uses 10s/5s on gateway and 15s elsewhere."
  type = object({
    interval            = optional(number, 15)
    timeout             = optional(number, 5)
    healthy_threshold   = optional(number, 2)
    unhealthy_threshold = optional(number, 3)
  })
  default = {}
}

variable "deregistration_delay" {
  description = "Seconds the target group waits for in-flight requests before deregistering a task."
  type        = number
  default     = 30
}

variable "listener_rule_priority" {
  description = "Priority of the forwarding rule on a shared listener. Must be unique per listener. Required when listener_arn is set."
  type        = number
  default     = null

  validation {
    condition     = var.listener_rule_priority == null || try(var.listener_rule_priority >= 1 && var.listener_rule_priority <= 50000, false)
    error_message = "listener_rule_priority must be between 1 and 50000."
  }
}

variable "listener_rule_host_headers" {
  description = "Host headers routed to this service, e.g. [\"gateway.dev.example.com\"]. Combined with path patterns when both are set."
  type        = list(string)
  default     = []
}

variable "listener_rule_path_patterns" {
  description = "Path patterns routed to this service, e.g. [\"/v1/*\"]. Combined with host headers when both are set."
  type        = list(string)
  default     = []
}

# ---------------------------------------------------------------------------
# Autoscaling
# ---------------------------------------------------------------------------

variable "autoscaling_min_capacity" {
  description = "Autoscaling floor. Prod SEA floors every service at 2."
  type        = number
  default     = 1

  validation {
    condition     = var.autoscaling_min_capacity >= 0
    error_message = "autoscaling_min_capacity cannot be negative."
  }
}

variable "autoscaling_max_capacity" {
  description = "Autoscaling ceiling. Prod SEA: gateway 18, next 12, identity 8, sessions 12."
  type        = number
  default     = 4

  validation {
    condition     = var.autoscaling_max_capacity >= 1
    error_message = "autoscaling_max_capacity must be at least 1."
  }
}

variable "cpu_target" {
  description = "Average CPU percentage to hold. Null disables the CPU policy. Prod SEA uses 55 everywhere."
  type        = number
  default     = 55
}

variable "memory_target" {
  description = "Average memory percentage to hold. Null disables the memory policy. Prod sets 70 on gateway only."
  type        = number
  default     = null
}

variable "requests_per_target" {
  description = "ALB requests per target to hold. Null disables the request policy. Requires listener_arn. Prod SEA: gateway 200, identity 300, sessions 400, next 500."
  type        = number
  default     = null
}

variable "scale_out_cooldown" {
  description = "Seconds after a scale-out before another may start. Prod SEA uses 60 everywhere."
  type        = number
  default     = 60
}

variable "scale_in_cooldown" {
  description = "Seconds after a scale-in before another may start. Prod SEA uses 300 on gateway and 600 elsewhere."
  type        = number
  default     = 600
}

variable "load_balancer_arn_suffix" {
  description = "ARN suffix of the load balancer, needed to build the ResourceLabel for the request-count policy. Required when requests_per_target is set."
  type        = string
  default     = null
}

# ---------------------------------------------------------------------------
# IAM
# ---------------------------------------------------------------------------

variable "task_role_policy_json" {
  description = "Inline policy for the task role — the permissions application code itself uses. Null attaches no inline policy."
  type        = string
  default     = null
}

variable "task_role_policy_arns" {
  description = "Managed policy ARNs attached to the task role."
  type        = list(string)
  default     = []
}

variable "secret_kms_key_arns" {
  description = "CMKs the execution role may decrypt when pulling secrets. Needed for any secret encrypted with a customer-managed key rather than the AWS-managed one."
  type        = list(string)
  default     = []
}

# ---------------------------------------------------------------------------
# Data store access
# ---------------------------------------------------------------------------

variable "data_store_ingress" {
  description = "Data stores this service may reach, keyed by a label used in the rule description. Creates an ingress rule on each store's own security group referencing this service's task security group. This is the direction that keeps the dependency graph acyclic: the store is built first with no clients, and the service grants itself access."
  type = map(object({
    security_group_id = string
    port              = number
  }))
  default = {}

  validation {
    condition     = alltrue([for s in values(var.data_store_ingress) : s.port > 0 && s.port <= 65535])
    error_message = "Every data_store_ingress port must be between 1 and 65535."
  }
}
