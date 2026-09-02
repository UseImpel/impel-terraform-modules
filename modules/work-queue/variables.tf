variable "max_receive_count" {
  description = "Receives before a message is moved to the DLQ."
  type        = number
  default     = 8

  validation {
    condition     = var.max_receive_count >= 1 && var.max_receive_count <= 1000
    error_message = "max_receive_count must be between 1 and 1000."
  }
}

variable "message_retention_seconds" {
  description = "Seconds SQS retains a message on the main queue. Default 14 days, the SQS maximum."
  type        = number
  default     = 1209600

  validation {
    condition     = var.message_retention_seconds >= 60 && var.message_retention_seconds <= 1209600
    error_message = "message_retention_seconds must be between 60 (1 minute) and 1209600 (14 days)."
  }
}

variable "name" {
  description = "Identifier for the queue, DLQ (-dlq suffix), KMS alias and IAM policies, e.g. impel-code-intelligence-dev-work."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{1,71}$", var.name))
    error_message = "name must be lowercase alphanumeric with hyphens, start with a letter, and leave room for -dlq (queue names are at most 80 characters)."
  }
}

variable "visibility_timeout_seconds" {
  description = "Seconds a received message stays hidden before it can be redelivered. Set above the worst-case job duration."
  type        = number
  default     = 120

  validation {
    condition     = var.visibility_timeout_seconds >= 0 && var.visibility_timeout_seconds <= 43200
    error_message = "visibility_timeout_seconds must be between 0 and 43200 (12 hours)."
  }
}
