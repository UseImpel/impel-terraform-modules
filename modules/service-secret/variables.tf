variable "name" {
  description = "Secret name, e.g. impel-gateway-dev/runtime. Prod SEA uses impel-<service>-sea/runtime."
  type        = string

  validation {
    condition     = can(regex("^[a-zA-Z0-9/_+=.@-]{1,512}$", var.name))
    error_message = "name may contain alphanumerics and / _ + = . @ - only."
  }
}

variable "description" {
  description = "What this secret holds. Shown in the Secrets Manager console."
  type        = string
}

variable "keys" {
  description = "Key names the service expects. Seeded with empty strings so the JSON shape exists and consumers referencing secret-arn:KEY:: resolve; real values are written out of band and never enter state."
  type        = list(string)
  default     = []
}

variable "kms_key_arn" {
  description = "CMK for the secret. Null uses the AWS-managed aws/secretsmanager key."
  type        = string
  default     = null
}

variable "recovery_window_days" {
  description = "Days a deleted secret is recoverable. Zero deletes immediately, which is what dev wants so a name can be reused straight away."
  type        = number
  default     = 30

  validation {
    condition     = var.recovery_window_days == 0 || (var.recovery_window_days >= 7 && var.recovery_window_days <= 30)
    error_message = "recovery_window_days must be 0, or between 7 and 30."
  }
}
