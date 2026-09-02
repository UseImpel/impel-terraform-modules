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
  description = "Elastic IPs of the NAT gateways. These are the addresses outbound traffic appears from, for allowlisting with third parties."
  value       = aws_eip.nat[*].public_ip
}
