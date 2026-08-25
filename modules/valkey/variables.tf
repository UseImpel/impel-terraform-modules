variable "name" {
  description = "Replication group identifier, e.g. impel-gateway-dev-redis."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{1,39}$", var.name))
    error_message = "name must be lowercase alphanumeric with hyphens, start with a letter, and be at most 40 characters."
  }
}

variable "description" {
  description = "What this cache is for. Shown in the ElastiCache console."
  type        = string
}

variable "vpc_id" {
  description = "VPC the security group belongs to."
  type        = string
}

variable "subnet_ids" {
  description = "Private subnets for the cache subnet group."
  type        = list(string)

  validation {
    condition     = length(var.subnet_ids) >= 1
    error_message = "At least one subnet is required; two or more for multi_az."
  }
}

variable "allowed_security_group_ids" {
  description = "Security groups permitted to reach the cache port. Task security groups go here; never a bare CIDR."
  type        = list(string)
  default     = []
}

variable "engine_version" {
  description = "Valkey engine version. Prod SEA runs Valkey rather than Redis OSS."
  type        = string
  default     = "8.0"
}

variable "node_type" {
  description = "Cache node type. Prod SEA uses cache.t4g.small; dev can drop to cache.t4g.micro."
  type        = string
  default     = "cache.t4g.small"

  validation {
    condition     = can(regex("^cache\\.[a-z0-9]+\\.[a-z]+$", var.node_type))
    error_message = "node_type must look like cache.t4g.small."
  }
}

variable "replica_count" {
  description = "Read replicas in the single node group. One replica is the minimum for multi_az and automatic failover."
  type        = number
  default     = 1

  validation {
    condition     = var.replica_count >= 0 && var.replica_count <= 5
    error_message = "replica_count must be between 0 and 5."
  }
}

variable "multi_az" {
  description = "Place replicas in other AZs and enable automatic failover. On in prod SEA. Requires replica_count of at least 1."
  type        = bool
  default     = true
}

variable "snapshot_retention_days" {
  description = "Days of automatic snapshots. Zero disables snapshots, which is fine for a pure cache."
  type        = number
  default     = 0

  validation {
    condition     = var.snapshot_retention_days >= 0 && var.snapshot_retention_days <= 35
    error_message = "snapshot_retention_days must be between 0 and 35."
  }
}

variable "parameters" {
  description = "Parameter overrides, applied to a dedicated parameter group."
  type        = map(string)
  default     = {}
}

variable "apply_immediately" {
  description = "Apply modifications at once instead of in the next maintenance window."
  type        = bool
  default     = false
}
