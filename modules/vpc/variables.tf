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

variable "nat_mode" {
  description = "How private subnets reach the internet. \"gateway\" (default): managed NAT gateways, as before this input existed. \"instance\": fck-nat on a Graviton instance in an Auto Scaling group of one per NAT, about $5/month (t4g.nano plus 8 GiB gp3) instead of about $43 plus $0.059/GB processed, at the cost of a 2-3 minute egress gap whenever the instance is replaced. Either way the NAT count follows single_nat_gateway and the NATs send from the same Elastic IPs; switching changes only the private routes' target."
  type        = string
  default     = "gateway"
  nullable    = false

  validation {
    condition     = contains(["gateway", "instance"], var.nat_mode)
    error_message = "nat_mode must be \"gateway\" or \"instance\"."
  }
}

variable "nat_eip_allocation_ids" {
  description = "Existing Elastic IP allocation IDs for the NATs to send from, one per NAT (one when single_nat_gateway is true, else one per AZ). Empty, the default, has the module create and own them (aws_eip.nat). Leave it empty on a VPC whose NAT EIPs this module already created: passing their IDs here plans their destruction, which releases the addresses. See README, \"Keeping the NAT's public IP\"."
  type        = list(string)
  default     = []
  nullable    = false

  validation {
    condition     = alltrue([for id in var.nat_eip_allocation_ids : can(regex("^eipalloc-[0-9a-f]+$", id))])
    error_message = "Every nat_eip_allocation_ids entry must be an allocation ID (eipalloc-...), not an address."
  }

  validation {
    condition     = length(var.nat_eip_allocation_ids) == 0 || length(var.nat_eip_allocation_ids) == (var.single_nat_gateway ? 1 : length(var.availability_zones))
    error_message = "nat_eip_allocation_ids needs exactly one allocation ID per NAT: one when single_nat_gateway is true, otherwise one per availability zone."
  }
}

variable "nat_instance_type" {
  description = "Instance type for nat_mode \"instance\". Graviton only, since the fck-nat AMI resolved here is arm64. t4g.nano bursts to 5 Gbps, which is plenty for a dev VPC."
  type        = string
  default     = "t4g.nano"
  nullable    = false

  validation {
    condition     = can(regex("^[a-z]+[0-9]+g[a-z0-9-]*\\.[a-z0-9]+$", var.nat_instance_type))
    error_message = "nat_instance_type must be a Graviton (arm64) instance type, e.g. t4g.nano."
  }
}

variable "nat_instance_ami_id" {
  description = "AMI ID for nat_mode \"instance\", pinning the image outright. Null, the default, resolves nat_instance_ami_name from nat_instance_ami_owner instead."
  type        = string
  default     = null
}

variable "nat_instance_ami_name" {
  description = "Exact fck-nat AMI name to resolve when nat_instance_ami_id is null. The name is identical in every region, so it pins the build without a per-region ID. Change it deliberately: a new image replaces the NAT instance (2-3 minutes without egress)."
  type        = string
  default     = "fck-nat-al2023-hvm-1.4.0-20260701-arm64-ebs"
  nullable    = false
}

variable "nat_instance_ami_owner" {
  description = "AWS account that publishes the fck-nat AMIs. The default is the fck-nat project's publishing account; resolving by name alone would accept any look-alike public image."
  type        = string
  default     = "568608671756"
  nullable    = false

  validation {
    condition     = can(regex("^[0-9]{12}$", var.nat_instance_ami_owner))
    error_message = "nat_instance_ami_owner must be a 12-digit AWS account ID."
  }
}

variable "nat_instance_root_volume_size" {
  description = "Root volume size in GiB for nat_mode \"instance\" (gp3, encrypted). The fck-nat image needs 4."
  type        = number
  default     = 8
  nullable    = false

  validation {
    condition     = var.nat_instance_root_volume_size >= 4 && floor(var.nat_instance_root_volume_size) == var.nat_instance_root_volume_size
    error_message = "nat_instance_root_volume_size must be a whole number of GiB, at least 4."
  }
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

variable "s3_gateway_endpoint_policy" {
  description = "IAM policy document attached to the S3 gateway endpoint, bounding what any principal in the VPC can do through it regardless of its own permissions. Null — the default — leaves the endpoint at AWS's full-access policy, the current behaviour. Ignored when enable_s3_gateway_endpoint is false."
  type        = string
  default     = null
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
