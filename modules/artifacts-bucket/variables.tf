variable "name" {
  description = "Base name for the IAM and KMS resources (artifact role, key alias, assume policy)."
  type        = string

  validation {
    condition     = can(regex("^[a-zA-Z0-9+=,.@_-]{1,64}$", var.name))
    error_message = "name must be a valid IAM role name (1-64 characters of [a-zA-Z0-9+=,.@_-])."
  }
}

variable "bucket_name" {
  description = "Globally unique S3 bucket name."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9.-]{1,61}[a-z0-9]$", var.bucket_name))
    error_message = "bucket_name must be a valid S3 bucket name."
  }
}

variable "lifecycle_rules" {
  description = "Per-prefix expiration rules. Each entry expires current and noncurrent objects under its prefix after expire_days; prefixes not listed never expire."
  type = list(object({
    prefix      = string
    expire_days = number
  }))
  default = []

  validation {
    condition = alltrue([
      for rule in var.lifecycle_rules :
      length(rule.prefix) > 0 && !startswith(rule.prefix, "/") && rule.expire_days >= 1
    ])
    error_message = "Each lifecycle rule needs a non-empty prefix without a leading slash and expire_days >= 1."
  }

  validation {
    condition     = length(var.lifecycle_rules) == length(distinct([for rule in var.lifecycle_rules : rule.prefix]))
    error_message = "Lifecycle rule prefixes must be unique."
  }
}

variable "reader_task_role_arns" {
  description = "Task-role ARNs allowed to assume the artifact role. ArnLike patterns are accepted."
  type        = list(string)

  validation {
    condition     = length(var.reader_task_role_arns) > 0
    error_message = "reader_task_role_arns must contain at least one role ARN."
  }

  validation {
    condition = alltrue([
      for arn in var.reader_task_role_arns : can(regex("^arn:[^:]+:iam::[0-9]{12}:role/", arn))
    ])
    error_message = "Each entry must be an IAM role ARN (arn:<partition>:iam::<account>:role/...)."
  }
}

variable "force_destroy" {
  description = "Allow Terraform to delete the bucket while it contains objects. Keep false for artifact safety."
  type        = bool
  default     = false
}
