variable "name" {
  description = "Globally unique S3 bucket name."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9.-]{1,61}[a-z0-9]$", var.name))
    error_message = "name must be a valid S3 bucket name."
  }
}

variable "prefix" {
  description = "Object key prefix covered by the IAM policy."
  type        = string
  default     = "orgs"

  validation {
    condition     = can(regex("^[a-zA-Z0-9!_.*'()/-]+$", var.prefix)) && !startswith(var.prefix, "/") && !endswith(var.prefix, "/")
    error_message = "prefix must be a non-empty key prefix without a leading or trailing slash."
  }
}

variable "force_destroy" {
  description = "Allow Terraform to delete the bucket while it contains objects. Keep false for payload safety."
  type        = bool
  default     = false
}
