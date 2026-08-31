variable "name" {
  description = "Name of the jump host, used for the instance, its security group, its IAM role and its instance profile."
  type        = string
}

variable "vpc_id" {
  description = "VPC the jump host and its security group live in. Must be the VPC holding the databases in database_ingress; a security group rule cannot reference a group in another VPC."
  type        = string
}

variable "subnet_id" {
  description = "Subnet the instance attaches to. A private subnet with a NAT route, or with the ssm, ssmmessages and ec2messages interface endpoints. A subnet with neither leaves the agent unable to register and the instance unreachable."
  type        = string
}

variable "database_ingress" {
  description = "Databases this host may forward to, keyed by a label used in the rule descriptions. Each entry creates an egress rule here and the matching ingress rule on the database's own security group. This map is the reachable set: a database absent from it cannot be tunnelled to, because port forwarding is limited by nothing else."
  type = map(object({
    security_group_id = string
    port              = number
  }))
  default = {}

  validation {
    condition     = alltrue([for d in values(var.database_ingress) : d.port > 0 && d.port <= 65535])
    error_message = "Every database_ingress port must be between 1 and 65535."
  }
}

variable "instance_type" {
  description = "Instance type. The default is the smallest current-generation Graviton size, which is the right one: this host runs an agent and proxies TCP, so CPU and memory are not what limits it. Graviton also costs less than the x86 equivalent, and the AMI parameter default resolves to a matching arm64 image -- change both together or the instance will not launch."
  type        = string
  default     = "t4g.nano"
}

variable "ami_ssm_parameter" {
  description = "SSM public parameter naming the AMI. Amazon Linux 2023 for arm64, which ships and starts the SSM agent with no user data. Resolved rather than pinned so a rebuild picks up a patched image; the instance ignores later changes, so a new AMI does not churn the plan. Must match the architecture of instance_type."
  type        = string
  default     = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-arm64"
}

variable "root_volume_size" {
  description = "Root volume size in GiB. The default is the AL2023 minimum: the host stores nothing, so a larger disk is only a larger bill."
  type        = number
  default     = 8

  validation {
    condition     = var.root_volume_size >= 8
    error_message = "The Amazon Linux 2023 image requires at least 8 GiB."
  }
}

variable "https_egress_cidr" {
  description = "Destination for the agent's outbound 443. Defaults to the internet, which is required when the agent reaches the public SSM endpoints through NAT. Narrow it to the VPC CIDR only if the VPC has the ssm, ssmmessages and ec2messages interface endpoints; without them, a VPC-scoped rule leaves the instance unable to register."
  type        = string
  default     = "0.0.0.0/0"

  validation {
    condition     = can(cidrnetmask(var.https_egress_cidr))
    error_message = "https_egress_cidr must be a valid IPv4 CIDR."
  }
}
