output "replication_group_id" {
  description = "Identifier of the replication group."
  value       = aws_elasticache_replication_group.this.id
}

output "primary_endpoint" {
  description = "Primary endpoint hostname. Clients must connect with TLS."
  value       = aws_elasticache_replication_group.this.primary_endpoint_address
}

output "reader_endpoint" {
  description = "Reader endpoint hostname. Null when no replicas exist."
  value       = aws_elasticache_replication_group.this.reader_endpoint_address
}

output "port" {
  description = "Port the replication group listens on."
  value       = aws_elasticache_replication_group.this.port
}

output "security_group_id" {
  description = "Security group fronting the cache. Grant clients ingress via allowed_security_group_ids."
  value       = aws_security_group.this.id
}

output "auth_token_secret_arn" {
  description = "ARN of the secret holding the auth token. Reference secret-arn:auth_token:: from a task definition."
  value       = aws_secretsmanager_secret.auth_token.arn
}

output "auth_token_secret_reference" {
  description = "Ready-made secret-arn:auth_token:: reference for the ecs-service module's container_secrets."
  value       = "${aws_secretsmanager_secret.auth_token.arn}:auth_token::"
}

output "kms_key_arn" {
  description = "CMK encrypting the cache at rest and the auth token secret."
  value       = aws_kms_key.this.arn
}

output "rest_token_secret_arn" {
  description = "ARN of the optional plain-string bearer token for a Redis REST adapter, or null when create_rest_token_secret is false."
  value       = one(aws_secretsmanager_secret.rest_token[*].arn)
  sensitive   = true
}
