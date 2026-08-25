output "repository_arn" {
  description = "ARN of the repository, for granting task execution roles pull access."
  value       = aws_ecr_repository.this.arn
}

output "repository_name" {
  description = "Name of the repository."
  value       = aws_ecr_repository.this.name
}

output "repository_url" {
  description = "Registry URL, e.g. 123456789012.dkr.ecr.ap-southeast-1.amazonaws.com/impel-gateway/dev. Append @sha256:... to pin an image by digest."
  value       = aws_ecr_repository.this.repository_url
}
