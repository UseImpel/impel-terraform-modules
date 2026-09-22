variable "name" {
  description = "Instance identifier, e.g. impel-gateway-dev-postgres-rds."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{1,61}$", var.name))
    error_message = "name must be lowercase alphanumeric with hyphens, start with a letter, and be at most 63 characters."
  }
}

variable "vpc_id" {
  description = "VPC the instance's security group belongs to."
  type        = string
}

variable "subnet_ids" {
  description = "Private subnets for the DB subnet group. At least two AZs -- RDS requires the group to span two even for a single-AZ instance."
  type        = list(string)

  validation {
    condition     = length(var.subnet_ids) >= 2
    error_message = "RDS requires a subnet group spanning at least two availability zones."
  }
}

variable "allowed_security_group_ids" {
  description = "Security groups permitted to reach the database port. Task security groups go here; never a bare CIDR."
  type        = list(string)
  default     = []
}

variable "engine_version" {
  description = "PostgreSQL version. Dev runs 17.9 to match the Aurora clusters this module replaces, so a pg_dump from Aurora restores without a version gap."
  type        = string
  default     = "17.9"
}

variable "instance_class" {
  description = "Instance class. db.t4g.micro is 1 GiB, matching the 0.5 ACU Aurora floor it replaces; db.t4g.small is 2 GiB for the clusters holding pooled connections around the clock."
  type        = string
  default     = "db.t4g.micro"

  validation {
    condition     = can(regex("^db\\.[a-z0-9]+\\.[a-z0-9]+$", var.instance_class))
    error_message = "instance_class must be an RDS instance class such as db.t4g.micro."
  }
}

variable "database_name" {
  description = "Name of the initial database created on the instance."
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

# 20 GiB is the gp3 minimum in every region this estate runs in, and it is the
# floor rather than a sizing decision: the largest database this module was
# written for holds under 500 MiB. Storage is bought in one block, so there is
# nothing to save by asking for less.
variable "allocated_storage" {
  description = "Provisioned storage in GiB. 20 is the gp3 minimum and includes 3000 IOPS at no extra charge."
  type        = number
  default     = 20

  validation {
    condition     = var.allocated_storage >= 20 && var.allocated_storage <= 65536
    error_message = "allocated_storage must be between 20 GiB (the gp3 minimum) and 65536 GiB."
  }
}

variable "max_allocated_storage" {
  description = "Ceiling for storage autoscaling in GiB. Zero disables autoscaling, which lets a filling disk take the database down instead. Must exceed allocated_storage when non-zero."
  type        = number
  default     = 100

  validation {
    condition     = var.max_allocated_storage == 0 || var.max_allocated_storage >= 20
    error_message = "max_allocated_storage must be 0 (autoscaling off) or at least 20 GiB."
  }
}

variable "multi_az" {
  description = "Run a standby in a second AZ. Doubles the instance cost and is a prod decision; dev runs single-AZ."
  type        = bool
  default     = false
}

variable "backup_retention_days" {
  description = "Automated backup retention. Backup storage up to the allocated storage size is free, so dev keeps 1 day at no cost."
  type        = number
  default     = 7

  validation {
    condition     = var.backup_retention_days >= 1 && var.backup_retention_days <= 35
    error_message = "backup_retention_days must be between 1 and 35."
  }
}

variable "deletion_protection" {
  description = "Refuse to delete the instance. On by default."
  type        = bool
  default     = true
}

variable "skip_final_snapshot" {
  description = "Skip the final snapshot on destroy. True only where losing the data is acceptable."
  type        = bool
  default     = false
}

variable "performance_insights_enabled" {
  description = "Enable Performance Insights. On by default; a db.t4g.micro dev instance reports little worth the charge."
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

variable "instance_parameters" {
  description = "Instance-level parameter overrides, applied to a dedicated parameter group. Note the family is postgres<major>, not aurora-postgresql<major>: Aurora-only parameters such as rds.logical_replication do not exist here."
  type        = map(string)
  default     = {}
}

variable "apply_immediately" {
  description = "Apply modifications at once instead of in the next maintenance window. Fine in dev; disruptive in prod."
  type        = bool
  default     = false
}

variable "master_password_rotation_days" {
  description = "Days between RDS-managed rotations of the master credential secret. Null keeps the RDS default of 7. Rotation cannot be switched off -- the secret is owned by RDS, so CancelRotateSecret is refused -- and 999 is the AWS maximum, which is how a dev account effectively opts out. Every consumer reads this password once at task start, so a rotation strands running tasks until they are redeployed."
  type        = number
  default     = null

  # A ternary, not `== null || (...)`. Terraform's || does not short-circuit:
  # it evaluates both operands, so the null default would fail the comparison
  # with "argument must not be null" for every caller that omits this variable.
  validation {
    condition     = var.master_password_rotation_days == null ? true : (var.master_password_rotation_days >= 1 && var.master_password_rotation_days <= 999)
    error_message = "master_password_rotation_days must be null, or between 1 and 999 (the Secrets Manager maximum rotation period)."
  }
}
