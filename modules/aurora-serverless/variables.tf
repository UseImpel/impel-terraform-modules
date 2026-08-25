variable "name" {
  description = "Cluster identifier, e.g. impel-gateway-dev-postgres."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{1,61}$", var.name))
    error_message = "name must be lowercase alphanumeric with hyphens, start with a letter, and be at most 63 characters."
  }
}

variable "vpc_id" {
  description = "VPC the cluster's security group belongs to."
  type        = string
}

variable "subnet_ids" {
  description = "Private subnets for the DB subnet group. At least two AZs."
  type        = list(string)

  validation {
    condition     = length(var.subnet_ids) >= 2
    error_message = "Aurora requires a subnet group spanning at least two availability zones."
  }
}

variable "allowed_security_group_ids" {
  description = "Security groups permitted to reach the database port. Task security groups go here; never a bare CIDR."
  type        = list(string)
  default     = []
}

variable "engine_version" {
  description = "Aurora PostgreSQL version. Prod SEA runs 17.9 across every cluster."
  type        = string
  default     = "17.9"
}

variable "database_name" {
  description = "Name of the initial database created in the cluster."
  type        = string
  default     = "impel"

  validation {
    condition     = can(regex("^[a-zA-Z][a-zA-Z0-9_]{0,62}$", var.database_name))
    error_message = "database_name must start with a letter and contain only letters, digits and underscores."
  }
}

variable "master_username" {
  description = "Master user. The password is generated and rotated by RDS, never set here."
  type        = string
  default     = "impel"

  validation {
    condition     = can(regex("^[a-zA-Z][a-zA-Z0-9_]{0,62}$", var.master_username))
    error_message = "master_username must start with a letter and contain only letters, digits and underscores."
  }
}

variable "min_capacity" {
  description = "Serverless v2 floor in ACUs. Prod SEA floors every cluster at 0.5."
  type        = number
  default     = 0.5

  validation {
    condition     = var.min_capacity >= 0 && var.min_capacity <= 256
    error_message = "min_capacity must be between 0 and 256 ACUs."
  }
}

variable "max_capacity" {
  description = "Serverless v2 ceiling in ACUs. Prod SEA uses 32 for gateway and 8 for next and sessions."
  type        = number
  default     = 8

  validation {
    condition     = var.max_capacity >= 0.5 && var.max_capacity <= 256
    error_message = "max_capacity must be between 0.5 and 256 ACUs."
  }
}

variable "reader_count" {
  description = "Reader instances alongside the writer. Prod SEA runs writer-only."
  type        = number
  default     = 0

  validation {
    condition     = var.reader_count >= 0 && var.reader_count <= 15
    error_message = "reader_count must be between 0 and 15."
  }
}

variable "backup_retention_days" {
  description = "Automated backup retention. Prod SEA keeps 35 days; dev has no reason to."
  type        = number
  default     = 7

  validation {
    condition     = var.backup_retention_days >= 1 && var.backup_retention_days <= 35
    error_message = "backup_retention_days must be between 1 and 35."
  }
}

variable "deletion_protection" {
  description = "Refuse to delete the cluster. On in prod SEA."
  type        = bool
  default     = true
}

variable "skip_final_snapshot" {
  description = "Skip the final snapshot on destroy. True only where losing the data is acceptable."
  type        = bool
  default     = false
}

variable "performance_insights_enabled" {
  description = "Enable Performance Insights on the instances. On in prod SEA."
  type        = bool
  default     = true
}

variable "monitoring_interval" {
  description = "Enhanced monitoring granularity in seconds. Zero disables it and skips the monitoring role."
  type        = number
  default     = 0

  validation {
    condition     = contains([0, 1, 5, 10, 15, 30, 60], var.monitoring_interval)
    error_message = "monitoring_interval must be one of 0, 1, 5, 10, 15, 30 or 60."
  }
}

variable "log_retention_days" {
  description = "Retention for the exported postgresql log group."
  type        = number
  default     = 30
}

variable "cluster_parameters" {
  description = "Cluster-level parameter overrides, applied to a dedicated parameter group."
  type        = map(string)
  default     = {}
}

variable "apply_immediately" {
  description = "Apply modifications at once instead of in the next maintenance window. Fine in dev; disruptive in prod."
  type        = bool
  default     = false
}
