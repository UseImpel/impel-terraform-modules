variable "name" {
  description = "Base name for the VPC and its child resources, e.g. impel-gateway-dev."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{1,60}$", var.name))
    error_message = "name must be lowercase alphanumeric with hyphens, starting with a letter."
  }
}

variable "cidr_block" {
  description = "IPv4 CIDR for the VPC. Prod SEA uses 10.90.0.0/16; dev uses 10.10.0.0/16."
  type        = string

  validation {
    condition     = can(cidrnetmask(var.cidr_block))
    error_message = "cidr_block must be a valid IPv4 CIDR, e.g. 10.10.0.0/16."
  }
}

variable "availability_zones" {
  description = "AZs to spread subnets across. One public and one private subnet is created per AZ."
  type        = list(string)

  validation {
    condition     = length(var.availability_zones) >= 2
    error_message = "At least two availability zones are required; ALBs and Aurora both demand it."
  }
}

variable "public_subnet_cidrs" {
  description = "Public subnet CIDRs, positionally matched to availability_zones."
  type        = list(string)

  validation {
    condition     = alltrue([for c in var.public_subnet_cidrs : can(cidrnetmask(c))])
    error_message = "Every public_subnet_cidrs entry must be a valid IPv4 CIDR."
  }
}

variable "private_subnet_cidrs" {
  description = "Private subnet CIDRs, positionally matched to availability_zones. Fargate tasks and data services live here."
  type        = list(string)

  validation {
    condition     = alltrue([for c in var.private_subnet_cidrs : can(cidrnetmask(c))])
    error_message = "Every private_subnet_cidrs entry must be a valid IPv4 CIDR."
  }
}

variable "single_nat_gateway" {
  description = "Route every private subnet through one NAT gateway. True matches prod SEA, which runs a single NAT; false creates one per AZ."
  type        = bool
  default     = true
}

variable "interface_endpoint_services" {
  description = "Short service names for interface VPC endpoints, e.g. ecr.api. Prod SEA runs ecr.api, ecr.dkr, logs and secretsmanager so tasks pull images and read secrets without traversing NAT."
  type        = list(string)
  default     = ["ecr.api", "ecr.dkr", "logs", "secretsmanager"]
}

variable "enable_s3_gateway_endpoint" {
  description = "Create the S3 gateway endpoint and associate it with the private route tables."
  type        = bool
  default     = true
}

variable "enable_flow_logs" {
  description = "Send VPC flow logs to CloudWatch Logs. Off in dev, where the log volume is not worth the spend."
  type        = bool
  default     = false
}

variable "flow_log_retention_days" {
  description = "Retention for the flow log group. Ignored when enable_flow_logs is false."
  type        = number
  default     = 30
}
