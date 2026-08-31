output "instance_id" {
  description = "Instance ID. This is the --target of an aws ssm start-session call."
  value       = aws_instance.this.id
}

output "private_ip" {
  description = "Private address of the jump host. Diagnostic only; nothing connects to it directly."
  value       = aws_instance.this.private_ip
}

output "security_group_id" {
  description = "Security group on the jump host. Referenced by the ingress rules this module writes onto each database's group."
  value       = aws_security_group.this.id
}

output "role_arn" {
  description = "ARN of the instance role. Grants the host access to SSM; it does not grant any human the right to open a session."
  value       = aws_iam_role.this.arn
}

output "role_name" {
  description = "Name of the instance role, for attaching further policies from the calling root."
  value       = aws_iam_role.this.name
}

output "operator_policy_arn" {
  description = "Customer-managed policy a human needs to open a port-forwarding session to this host. Attach it to the SSO permission set or role your developers assume; nobody can connect until it is attached. It permits the port-forwarding document on this instance only, so it grants no shell."
  value       = aws_iam_policy.operator.arn
}

output "operator_policy_name" {
  description = "Name of the operator policy, for attaching by name from a permission set defined outside this account."
  value       = aws_iam_policy.operator.name
}

output "reachable_databases" {
  description = "Labels from database_ingress that this host can forward to. A database missing here is unreachable no matter what a session requests."
  value       = sort(keys(var.database_ingress))
}
