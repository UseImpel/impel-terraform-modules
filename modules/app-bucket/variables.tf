variable "name" {
  description = "Bucket name. Must be globally unique. Callers include the account ID, e.g. impel-gateway-dev-bifrost-logs-123456789012."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9.-]{1,61}[a-z0-9]$", var.name))
    error_message = "name must be a valid S3 bucket name: 3–63 characters, lowercase alphanumeric, dots and hyphens, starting and ending alphanumeric."
  }
}

variable "prefix" {
  description = "Key prefix application objects are written under, with no leading slash. Empty applies the IAM policy and lifecycle to the whole bucket."
  type        = string
  default     = ""

  validation {
    condition     = var.prefix == "" || can(regex("^[a-zA-Z0-9!_.*'()/-]+$", var.prefix)) && !startswith(var.prefix, "/")
    error_message = "prefix must be empty or a key prefix with no leading slash."
  }
}

variable "retention_days" {
  description = "Days before current objects and noncurrent versions expire. Match the application's own retention. null keeps objects and noncurrent versions forever: the lifecycle rule then only aborts incomplete multipart uploads."
  type        = number
  default     = 14
  nullable    = true

  validation {
    # try(): an explicit null must not reach the comparisons.
    condition     = var.retention_days == null || try(var.retention_days >= 1 && var.retention_days <= 3650, false)
    error_message = "retention_days must be null (no expiry) or between 1 and 3650."
  }
}

variable "iam_role_names" {
  description = "Existing IAM role names that receive the object-access policy. Use this when the task role lives outside this stack (a CDK service in prod). Leave empty and pass iam_policy_arn to ecs-service.task_role_policy_arns when this stack owns the role."
  type        = list(string)
  default     = []
}

variable "force_destroy" {
  description = "Allow Terraform to delete the bucket while it still holds objects. Leave false; lifecycle expiry (when retention_days is set) is what empties it."
  type        = bool
  default     = false
}
