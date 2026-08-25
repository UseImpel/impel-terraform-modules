variable "name" {
  description = "Identifier for the queue (without .fifo), DLQ, KMS alias and IAM policy, e.g. impel-next-dev-inbound-events."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{1,61}$", var.name)) && !endswith(var.name, ".fifo")
    error_message = "name must be lowercase alphanumeric with hyphens, start with a letter, omit the .fifo suffix, and leave room for -dlq.fifo (FIFO names are at most 80 characters)."
  }
}

variable "bucket_name" {
  description = "Overflow bucket name. Must be globally unique; callers include the account ID."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9.-]{1,61}[a-z0-9]$", var.bucket_name))
    error_message = "bucket_name must be a valid S3 bucket name: 3–63 characters, lowercase alphanumeric, dots and hyphens, starting and ending alphanumeric."
  }
}

variable "prefix" {
  description = "Key prefix overflow objects are written under, with no leading slash. Next writes inbound-events/."
  type        = string
  default     = "inbound-events"

  validation {
    condition     = can(regex("^[a-zA-Z0-9!_.*'()/-]+$", var.prefix)) && !startswith(var.prefix, "/") && !endswith(var.prefix, "/")
    error_message = "prefix must be a key prefix with no leading or trailing slash."
  }
}

variable "object_retention_days" {
  description = "Days before current overflow objects expire. Prod Next inbound is 14."
  type        = number
  default     = 14

  validation {
    condition     = var.object_retention_days >= 1 && var.object_retention_days <= 3650
    error_message = "object_retention_days must be between 1 and 3650."
  }
}

variable "noncurrent_retention_days" {
  description = "Days before noncurrent overflow versions expire. Prod Next inbound is 30."
  type        = number
  default     = 30

  validation {
    condition     = var.noncurrent_retention_days >= 1 && var.noncurrent_retention_days <= 3650
    error_message = "noncurrent_retention_days must be between 1 and 3650."
  }
}

variable "force_destroy" {
  description = "Allow Terraform to delete the overflow bucket while it still holds objects. Leave false; lifecycle expiry is what empties it."
  type        = bool
  default     = false
}
