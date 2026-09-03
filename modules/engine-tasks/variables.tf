variable "name_prefix" {
  description = "Estate name prefix, e.g. impel-code-intelligence-dev. Families become <name_prefix>-engine-<key>."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{1,42}$", var.name_prefix))
    error_message = "name_prefix must be lowercase alphanumeric with hyphens, begin with a letter, and leave room for derived IAM role and policy names."
  }
}

variable "tasks" {
  description = "Engine fleet task definitions, keyed by engine name (checkout, toolbox, zoekt, ...). Each entry becomes one Fargate task definition family <name_prefix>-engine-<key>. The key \"checkout\" is special: its family is granted to the worker policy only, never to query."
  type = map(object({
    image         = string
    cpu           = number
    memory        = number
    ephemeral_gib = number
    entrypoint    = list(string)
  }))

  validation {
    condition     = length(var.tasks) > 0
    error_message = "tasks must contain at least one engine."
  }

  validation {
    condition     = alltrue([for k in keys(var.tasks) : can(regex("^[a-z0-9-]{1,64}$", k))])
    error_message = "task keys become family suffixes and log stream prefixes; lowercase alphanumeric with hyphens only."
  }

  validation {
    condition     = alltrue([for t in values(var.tasks) : length(t.image) > 0])
    error_message = "every task needs a non-empty image reference."
  }

  validation {
    condition     = alltrue([for t in values(var.tasks) : length(t.entrypoint) > 0])
    error_message = "every task needs a non-empty entrypoint (the CDK fleet uses [\"aws-engine\"])."
  }

  validation {
    condition     = alltrue([for t in values(var.tasks) : t.ephemeral_gib >= 21 && t.ephemeral_gib <= 200])
    error_message = "ephemeral_gib must be 21-200; Fargate rejects anything else on the ephemeralStorage override."
  }

  validation {
    condition = alltrue([for t in values(var.tasks) : contains([
      "256:512", "256:1024", "256:2048",
      "512:1024", "512:2048", "512:3072", "512:4096",
      "1024:2048", "1024:3072", "1024:4096", "1024:5120", "1024:6144", "1024:7168", "1024:8192",
      "2048:4096", "2048:5120", "2048:6144", "2048:7168", "2048:8192", "2048:9216", "2048:10240", "2048:11264", "2048:12288", "2048:13312", "2048:14336", "2048:15360", "2048:16384",
      "4096:8192", "4096:9216", "4096:10240", "4096:11264", "4096:12288", "4096:13312", "4096:14336", "4096:15360", "4096:16384", "4096:17408", "4096:18432", "4096:19456", "4096:20480", "4096:21504", "4096:22528", "4096:23552", "4096:24576", "4096:25600", "4096:26624", "4096:27648", "4096:28672", "4096:29696", "4096:30720"
    ], "${t.cpu}:${t.memory}")])
    error_message = "Each task cpu/memory pair must be Fargate-compatible."
  }
}

variable "ecr_repository_arns" {
  description = "ECR repository ARNs the shared engine execution role may pull. The role still needs ecr:GetAuthorizationToken on *, but layer and manifest reads remain limited to these repositories."
  type        = list(string)

  validation {
    condition     = length(var.ecr_repository_arns) > 0
    error_message = "ecr_repository_arns must contain at least one repository ARN."
  }
}

variable "engine_container_name" {
  description = "Container name inside every engine task definition. The worker/query services address the container by this name in their RunTask overrides (CODE_INTELLIGENCE_AWS_ENGINE_CONTAINER_NAME)."
  type        = string
  default     = "engine"

  validation {
    condition     = can(regex("^[a-zA-Z0-9_-]{1,255}$", var.engine_container_name))
    error_message = "engine_container_name must be a valid ECS container name."
  }
}

variable "log_retention_days" {
  description = "Retention on the shared engine log group. Dev keeps 7 days; one-off engine tasks are debugged the same day they run."
  type        = number
  default     = 7
}

variable "vpc_id" {
  description = "VPC the checkout and engine security groups live in."
  type        = string

  validation {
    condition     = can(regex("^vpc-", var.vpc_id))
    error_message = "vpc_id must be a VPC id."
  }
}

variable "vpc_dns_cidr" {
  description = "The VPC resolver address as a /32, e.g. 10.90.0.2/32 (VPC CIDR base + 2). The engine security group's only DNS egress target."
  type        = string

  validation {
    condition     = can(cidrhost(var.vpc_dns_cidr, 0)) && endswith(var.vpc_dns_cidr, "/32")
    error_message = "vpc_dns_cidr must be a single-host /32 CIDR, e.g. 10.90.0.2/32."
  }
}

variable "endpoint_security_group_id" {
  description = "Security group on the shared ECR and CloudWatch Logs interface endpoints. Engine tasks may open 443 to this group and nothing else on the interface-endpoint path."
  type        = string

  validation {
    condition     = can(regex("^sg-", var.endpoint_security_group_id))
    error_message = "endpoint_security_group_id must be a security group id."
  }
}

variable "s3_prefix_list_id" {
  description = "Managed prefix list of the regional S3 gateway endpoint (pl-...). Engine tasks reach S3 only through it, for presigned artifact transfers."
  type        = string

  validation {
    condition     = can(regex("^pl-", var.s3_prefix_list_id))
    error_message = "s3_prefix_list_id must be a managed prefix list id."
  }
}

variable "cluster_arn" {
  description = "Cluster the engine tasks are allowed to start on. Used as the ecs:cluster condition on RunTask/DescribeTasks/StopTask so the service roles cannot launch or manage these families elsewhere."
  type        = string

  validation {
    condition     = can(regex("^arn:aws:ecs:[a-z0-9-]+:[0-9]{12}:cluster/", var.cluster_arn))
    error_message = "cluster_arn must be an ECS cluster ARN."
  }
}

variable "application_tag" {
  description = "Required value of the Application request tag on every RunTask call. The RunTask condition keys tie each launched task to this application."
  type        = string
  default     = "code-intelligence"

  validation {
    condition     = length(var.application_tag) > 0
    error_message = "application_tag cannot be empty."
  }
}
