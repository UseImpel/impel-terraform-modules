variable "name" {
  description = "Cluster, ACL and subnet-group identifier, e.g. impel-next-dev."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{1,39}$", var.name))
    error_message = "name must be lowercase alphanumeric with hyphens, start with a letter, and be at most 40 characters."
  }
}

variable "description" {
  description = "What this cluster is for. Shown in the MemoryDB console."
  type        = string
}

variable "vpc_id" {
  description = "VPC the security group belongs to."
  type        = string
}

variable "subnet_ids" {
  description = "Private subnets for the MemoryDB subnet group. MemoryDB requires at least two, in different AZs."
  type        = list(string)

  validation {
    condition     = length(var.subnet_ids) >= 2
    error_message = "MemoryDB needs at least two subnets in different availability zones."
  }
}

variable "allowed_security_group_ids" {
  description = "Security groups permitted to reach the cluster port. Task security groups go here; never a bare CIDR. Leave empty and grant from ecs-service data_store_ingress when the caller also reads this module's outputs (avoids a cycle)."
  type        = list(string)
  default     = []
}

variable "user_name" {
  description = "ACL user the application authenticates as. Next's ioredis client hardcodes impel-next; do not change that without changing the app."
  type        = string
  default     = "impel-next"

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{0,39}$", var.user_name))
    error_message = "user_name must be lowercase alphanumeric with hyphens, start with a letter, and be at most 40 characters."
  }
}

variable "engine_version" {
  description = "Redis engine version. Prod Next MemoryDB runs 7.1."
  type        = string
  default     = "7.1"
}

variable "node_type" {
  description = "MemoryDB node type. Prod Next uses db.r7g.large; CDK also allows db.t4g.small for a smaller footprint."
  type        = string
  default     = "db.t4g.small"

  validation {
    condition     = can(regex("^db\\.[a-z0-9]+\\.[a-z]+$", var.node_type))
    error_message = "node_type must look like db.t4g.small."
  }
}

variable "num_shards" {
  description = "Number of shards. Prod Next and the Next client assume one shard."
  type        = number
  default     = 1

  validation {
    condition     = var.num_shards >= 1 && var.num_shards <= 500
    error_message = "num_shards must be between 1 and 500."
  }
}

variable "num_replicas_per_shard" {
  description = "Replicas per shard. Prod Next runs 1; 0 is valid for a disposable cluster (still CLUSTER-protocol)."
  type        = number
  default     = 0

  validation {
    condition     = var.num_replicas_per_shard >= 0 && var.num_replicas_per_shard <= 5
    error_message = "num_replicas_per_shard must be between 0 and 5."
  }
}

variable "snapshot_retention_days" {
  description = "Days of automatic snapshots. Zero disables snapshots. Prod Next keeps 35."
  type        = number
  default     = 0

  validation {
    condition     = var.snapshot_retention_days >= 0 && var.snapshot_retention_days <= 35
    error_message = "snapshot_retention_days must be between 0 and 35."
  }
}
