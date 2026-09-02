variable "name" {
  description = "Filesystem identifier, also the base name of its security group, e.g. impel-meets-dev-data."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{1,61}$", var.name))
    error_message = "name must be lowercase alphanumeric with hyphens, start with a letter, and be at most 62 characters — EFS creation tokens cap at 64."
  }
}

variable "vpc_id" {
  description = "VPC the filesystem's security group belongs to."
  type        = string
}

variable "subnet_ids" {
  description = "Private subnets to place mount targets in. One mount target per subnet; EFS allows at most one per availability zone."
  type        = list(string)

  validation {
    condition     = length(var.subnet_ids) >= 1
    error_message = "At least one subnet is required."
  }
}

variable "allowed_security_group_id" {
  description = "The one security group permitted to reach the filesystem's NFS port. Task security groups go here; never a bare CIDR."
  type        = string
}

variable "kms_key_arn" {
  description = "CMK encrypting the filesystem at rest. Null uses the AWS-managed aws/elasticfilesystem key."
  type        = string
  default     = null
}

variable "access_points" {
  description = "Access points to create, keyed by a stable label used in resource naming, e.g. postgres-data. Each pins a POSIX uid/gid on mount and creates its root directory with matching ownership if absent."
  type = map(object({
    root_directory_path = string
    uid                 = number
    gid                 = number
    permissions         = optional(string, "0755")
  }))

  validation {
    condition     = alltrue([for ap in values(var.access_points) : can(regex("^/", ap.root_directory_path))])
    error_message = "Every access point's root_directory_path must be an absolute path starting with /."
  }

  validation {
    condition     = alltrue([for ap in values(var.access_points) : ap.uid >= 0 && ap.gid >= 0])
    error_message = "Every access point's uid and gid must be non-negative."
  }

  validation {
    condition     = alltrue([for ap in values(var.access_points) : can(regex("^[0-7]{3,4}$", ap.permissions))])
    error_message = "Every access point's permissions must be an octal mode such as 0755."
  }
}
