variable "name" {
  description = "Repository name, e.g. impel-gateway/dev. Prod SEA uses impel-<service>/sea."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9._/-]{1,255}$", var.name))
    error_message = "name must be lowercase and may contain dots, underscores, hyphens and slashes."
  }
}

variable "image_tag_mutability" {
  description = "IMMUTABLE prevents a tag being repointed at a different digest. Prod SEA uses IMMUTABLE for release repos and MUTABLE for build caches."
  type        = string
  default     = "IMMUTABLE"

  validation {
    condition     = contains(["IMMUTABLE", "MUTABLE"], var.image_tag_mutability)
    error_message = "image_tag_mutability must be IMMUTABLE or MUTABLE."
  }
}

variable "scan_on_push" {
  description = "Run a basic vulnerability scan on push. On for release repos in prod SEA, off for build caches."
  type        = bool
  default     = true
}

variable "kms_key_arn" {
  description = "CMK for repository encryption. Null uses AES256 with an AWS-owned key, which is what prod SEA does."
  type        = string
  default     = null
}

variable "force_delete" {
  description = "Allow Terraform to delete the repository while it still holds images. Reasonable in dev, never in prod."
  type        = bool
  default     = false
}

variable "untagged_image_expiry_days" {
  description = "Expire untagged images after this many days. Zero disables the lifecycle policy."
  type        = number
  default     = 14

  validation {
    condition     = var.untagged_image_expiry_days >= 0
    error_message = "untagged_image_expiry_days cannot be negative."
  }
}

variable "max_tagged_images" {
  description = "Keep at most this many tagged images, expiring the oldest. Zero leaves tagged images alone."
  type        = number
  default     = 0

  validation {
    condition     = var.max_tagged_images >= 0
    error_message = "max_tagged_images cannot be negative."
  }
}

variable "pull_account_ids" {
  description = "Account IDs granted pull access through a repository policy. Used to let a dev account pull images built into a prod-owned repo."
  type        = list(string)
  default     = []

  validation {
    condition     = alltrue([for a in var.pull_account_ids : can(regex("^[0-9]{12}$", a))])
    error_message = "Every pull_account_ids entry must be exactly 12 digits."
  }
}
