output "role_arn" {
  description = "ARN the application repository's workflow assumes. Pass to aws-actions/configure-aws-credentials as role-to-assume; the workflow needs permissions: id-token: write to receive an OIDC token at all."
  value       = aws_iam_role.this.arn
}

output "role_name" {
  description = "Name of the deploy role."
  value       = aws_iam_role.this.name
}

output "trusted_subject" {
  description = "The single OIDC subject the trust policy accepts. A run whose token carries anything else is refused by STS, so this is the exact repository and branch that can deploy."
  value       = local.subject
}
