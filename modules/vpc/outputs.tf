output "vpc_id" {
  description = "ID of the VPC."
  value       = aws_vpc.this.id
}

output "vpc_cidr_block" {
  description = "IPv4 CIDR of the VPC."
  value       = aws_vpc.this.cidr_block
}

output "public_subnet_ids" {
  description = "Public subnet IDs, in availability_zones order. Load balancers attach here."
  value       = aws_subnet.public[*].id
}

output "private_subnet_ids" {
  description = "Private subnet IDs, in availability_zones order. Fargate tasks and data services attach here."
  value       = aws_subnet.private[*].id
}

output "private_route_table_ids" {
  description = "Private route table IDs, for callers adding gateway endpoints of their own."
  value       = aws_route_table.private[*].id
}

output "vpc_endpoint_security_group_id" {
  description = "Security group fronting the interface VPC endpoints."
  value       = aws_security_group.endpoints.id
}

output "s3_gateway_prefix_list_id" {
  description = "Prefix list ID of the S3 gateway endpoint, for security group rules that allow S3 without opening 0.0.0.0/0. Null when enable_s3_gateway_endpoint is false."
  value       = one(aws_vpc_endpoint.s3[*].prefix_list_id)
}

output "nat_gateway_public_ips" {
  description = "Elastic IPs the NATs send from, in either nat_mode (the name predates nat_mode). These are the addresses outbound traffic appears from, for allowlisting with third parties."
  value       = local.nat_public_ips
}

output "nat_eip_allocation_ids" {
  description = "Allocation IDs of the Elastic IPs the NATs send from: the caller's nat_eip_allocation_ids, or the module's own."
  value       = local.nat_eip_allocation_ids
}

output "nat_mode" {
  description = "The NAT implementation in use: \"gateway\" or \"instance\"."
  value       = var.nat_mode
}

output "nat_gateway_ids" {
  description = "Managed NAT gateway IDs. Empty in nat_mode \"instance\"."
  value       = aws_nat_gateway.this[*].id
}

output "nat_instance_network_interface_ids" {
  description = "Static ENIs the private routes target in nat_mode \"instance\" (for alarms on the NAT's traffic). Empty in nat_mode \"gateway\"."
  value       = aws_network_interface.nat[*].id
}

output "nat_instance_autoscaling_group_names" {
  description = "Auto Scaling groups running the fck-nat instances in nat_mode \"instance\". Empty in nat_mode \"gateway\"."
  value       = aws_autoscaling_group.nat[*].name
}
