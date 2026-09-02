# ---------------------------------------------------------------------------
# Identity and placement
# ---------------------------------------------------------------------------

variable "name" {
  description = "Service name, also the task definition family and the base of every child resource, e.g. impel-meets-dev."
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
# Containers
#
# Unlike ecs-service's single primary container plus optional sidecars, every
# container here is a first-class, independently-sized member of the task:
# the meets data plane is ten interdependent containers, each essential, each
# with its own cpu/memory reservation. The map key is the container name.
# ---------------------------------------------------------------------------

variable "cpu" {
  description = "Task CPU units, the sum the platform reserves for the whole task. Fargate accepts 256, 512, 1024, 2048, 4096, 8192 and 16384."
  type        = number

  validation {
    condition     = contains([256, 512, 1024, 2048, 4096, 8192, 16384], var.cpu)
    error_message = "cpu must be one of 256, 512, 1024, 2048, 4096, 8192 or 16384."
  }
}

variable "memory" {
  description = "Task memory in MiB, the sum the platform reserves for the whole task. Must be a valid pairing for the chosen cpu."
  type        = number

  validation {
    condition     = var.memory >= 512 && var.memory <= 122880
    error_message = "memory must be between 512 and 122880 MiB."
  }
}

variable "containers" {
  description = "Every container in the task, keyed by container name. Each is essential: true — this module has no optional-container concept, because the meets shape has none. Per-container cpu/memory are soft reservations that must not exceed the task-level cpu/memory once summed."
  type = map(object({
    image                     = string
    cpu                       = number
    memory                    = number
    port                      = optional(number)
    command                   = optional(list(string), [])
    entrypoint                = optional(list(string), [])
    environment_variables     = optional(map(string), {})
    secrets                   = optional(map(string), {})
    health_check_command      = optional(list(string), [])
    health_check_interval     = optional(number, 30)
    health_check_timeout      = optional(number, 5)
    health_check_retries      = optional(number, 3)
    health_check_start_period = optional(number, 60)
    stop_timeout              = optional(number)
    readonly_root_filesystem  = optional(bool, false)
    depends_on = optional(list(object({
      container_name = string
      condition      = string
    })), [])
    mount_points = optional(list(object({
      volume_name    = string
      container_path = string
      read_only      = optional(bool, false)
    })), [])
  }))

  validation {
    condition     = alltrue([for c in values(var.containers) : c.port == null || (c.port > 0 && c.port <= 65535)])
    error_message = "Every container port must be between 1 and 65535."
  }

  validation {
    condition     = alltrue([for c in values(var.containers) : c.stop_timeout == null || (c.stop_timeout >= 2 && c.stop_timeout <= 120)])
    error_message = "Every container stop_timeout must be null, or between 2 and 120 seconds — the Fargate maximum."
  }

  validation {
    condition = alltrue(flatten([
      for c in values(var.containers) : [
        for d in c.depends_on : contains(["START", "COMPLETE", "SUCCESS", "HEALTHY"], d.condition)
      ]
    ]))
    error_message = "Every container dependsOn condition must be START, COMPLETE, SUCCESS, or HEALTHY."
  }

  validation {
    condition = alltrue(flatten([
      for c in values(var.containers) : [
        for d in c.depends_on : contains(keys(var.containers), d.container_name)
      ]
    ]))
    error_message = "Every container dependsOn must name another key in var.containers."
  }
}

variable "primary_container_name" {
  description = "Key in var.containers that the load balancer forwards to. Its port drives the task security group's inbound rule, the target group, and the service's load_balancer block."
  type        = string
}

variable "volumes" {
  description = "EFS-backed volumes the task can mount, keyed by the name var.containers[*].mount_points[*].volume_name references. Pass an efs-volume module's file_system_id and one of its access_point_ids per entry."
  type = map(object({
    file_system_id     = string
    access_point_id    = string
    transit_encryption = optional(bool, true)
    iam_authorization  = optional(bool, false)
  }))
  default = {}
}

variable "ephemeral_storage_gib" {
  description = "Task ephemeral storage. Prod's meets task reserves 40 for the postgres/minio/bridge volumes' local overhead and container image layers."
  type        = number
  default     = 40

  validation {
    condition     = var.ephemeral_storage_gib >= 21 && var.ephemeral_storage_gib <= 200
    error_message = "ephemeral_storage_gib must be between 21 and 200."
  }
}

# ---------------------------------------------------------------------------
# Service
#
# Deployment posture is not a variable here. KTD2 fixes 100/0 (stop-then-
# start) and disables AZ rebalancing because the task holds the sole writer
# to its own EFS-backed postgres and minio volumes: a second task started
# before the first stops would fight it for those mounts. ecs-service's
# 100/200 rolling default is unsafe for this shape, which is the reason this
# module exists instead of a flag on that one. desired_count is fixed at 1
# for the same reason and is not exposed as a variable.
# ---------------------------------------------------------------------------

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
  description = "Fargate platform version."
  type        = string
  default     = "LATEST"
}

variable "health_check_grace_period" {
  description = "Seconds before load balancer health checks can kill a new task. A ten-container task with a dependsOn chain from postgres through gateway needs longer than ecs-service's single-container default."
  type        = number
  default     = 900
}

variable "enable_execute_command" {
  description = "Allow aws ecs execute-command into running tasks."
  type        = bool
  default     = true
}

variable "continuous_deployment" {
  description = "Let the service's own application repository roll new images. When true, Terraform stops reconciling which task definition revision the service runs, so an `aws ecs update-service` from a merge pipeline survives the next apply. Leave false to keep the digest in this repository authoritative."
  type        = bool
  default     = false
}

variable "log_retention_days" {
  description = "Retention for the service log group."
  type        = number
  default     = 30

  validation {
    condition     = contains([1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1096, 1827, 2192, 2557, 2922, 3288, 3653], var.log_retention_days)
    error_message = "log_retention_days must be a retention period CloudWatch Logs accepts."
  }
}

variable "log_group_name" {
  description = "Override the log group name. Null derives /ecs/<name>/service."
  type        = string
  default     = null
}

# ---------------------------------------------------------------------------
# Load balancer
# ---------------------------------------------------------------------------

variable "attach_load_balancer" {
  description = "Put this service behind a load balancer, creating a target group, a listener rule and ALB ingress on the task security group. Must be a literal the caller sets, not derived from another resource: it drives count and has to resolve at plan time."
  type        = bool
  default     = true
}

variable "listener_arn" {
  description = "Listener to attach the forwarding rule to. Required when attach_load_balancer is true."
  type        = string
  default     = null
}

variable "load_balancer_security_group_id" {
  description = "Security group of the load balancer. The task security group accepts the primary container's port from this and nothing else. Required when listener_arn is set."
  type        = string
  default     = null
}

variable "health_check_path" {
  description = "Target group health check path."
  type        = string
  default     = "/health"
}

variable "health_check_matcher" {
  description = "HTTP codes counted as healthy."
  type        = string
  default     = "200-299"
}

variable "target_group_health_check" {
  description = "Target group health check timing."
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
  description = "Host headers routed to this service, e.g. [\"meets.dev.example.com\"]. Combined with path patterns when both are set."
  type        = list(string)
  default     = []
}

variable "listener_rule_path_patterns" {
  description = "Path patterns routed to this service, e.g. [\"/v1/*\"]. Combined with host headers when both are set."
  type        = list(string)
  default     = []
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
