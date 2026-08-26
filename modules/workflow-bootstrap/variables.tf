variable "family" {
  description = "Task definition family, e.g. impel-next-dev-workflow-bootstrap."
  type        = string

  validation {
    condition     = can(regex("^[a-zA-Z0-9_-]{1,255}$", var.family))
    error_message = "family must be alphanumeric with hyphens or underscores, max 255 characters."
  }
}

variable "container_image" {
  description = "Image the one-shot task runs, including tag. Dev uses a mutable tag (bootstrap) that the application repository moves."
  type        = string

  validation {
    condition     = length(var.container_image) > 0
    error_message = "container_image cannot be empty."
  }
}

variable "cpu" {
  description = "Fargate CPU units. 512 is enough for Drizzle + Graphile migrate on a small Aurora."
  type        = number
  default     = 512

  validation {
    condition     = contains([256, 512, 1024, 2048, 4096], var.cpu)
    error_message = "cpu must be a valid Fargate CPU value."
  }
}

variable "memory" {
  description = "Fargate memory in MiB. Must be a valid pairing with cpu."
  type        = number
  default     = 1024

  validation {
    condition     = var.memory >= 512
    error_message = "memory must be at least 512 MiB."
  }
}

variable "execution_role_arn" {
  description = "Existing task execution role that already pulls this repository and decrypts the workflow database secret. Reused so the one-shot does not get a second identity."
  type        = string

  validation {
    condition     = can(regex("^arn:aws:iam::[0-9]{12}:role/", var.execution_role_arn))
    error_message = "execution_role_arn must be an IAM role ARN."
  }
}

variable "task_role_arn" {
  description = "Existing task role passed to the one-shot. setupDatabase talks to Aurora with credentials from the execution role; this is required so PassRole matches the deploy role's grant."
  type        = string

  validation {
    condition     = can(regex("^arn:aws:iam::[0-9]{12}:role/", var.task_role_arn))
    error_message = "task_role_arn must be an IAM role ARN."
  }
}

variable "log_group_name" {
  description = "Existing CloudWatch log group. Reuse the long-running service's group so the execution role's logs:PutLogEvents grant already covers this task."
  type        = string
}

variable "environment_variables" {
  description = "Plain environment for the bootstrap container. Must include IMPEL_WORKFLOW_DATABASE_HOST and IMPEL_WORKFLOW_DATABASE_NAME."
  type        = map(string)
  default     = {}
}

variable "container_secrets" {
  description = "Secrets injected into the bootstrap container. Must include IMPEL_WORKFLOW_DATABASE_CREDENTIALS_JSON pointing at the RDS-managed credentials ARN."
  type        = map(string)
  default     = {}
}

variable "deploy_role_name" {
  description = "GitHub deploy role that may RunTask this family. The extra grant is attached here because github-deploy-role has no RunTask input."
  type        = string
}

variable "cluster_arn" {
  description = "Cluster the one-shot is allowed to start on. Used as the ecs:cluster condition on RunTask so the deploy role cannot launch this family elsewhere."
  type        = string

  validation {
    condition     = can(regex("^arn:aws:ecs:", var.cluster_arn))
    error_message = "cluster_arn must be an ECS cluster ARN."
  }
}
