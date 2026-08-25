output "cluster_name" {
  description = "MemoryDB cluster name."
  value       = aws_memorydb_cluster.this.name
}

output "cluster_endpoint" {
  description = "Cluster configuration endpoint hostname (clustercfg.…). Clients must use this with TLS and CLUSTER discovery, not a node endpoint."
  value       = aws_memorydb_cluster.this.cluster_endpoint[0].address
}

output "port" {
  description = "Port the cluster listens on."
  value       = aws_memorydb_cluster.this.cluster_endpoint[0].port
}

output "user_name" {
  description = "ACL user the application authenticates as."
  value       = aws_memorydb_user.this.user_name
}

output "security_group_id" {
  description = "Security group fronting the cluster. Grant clients ingress via allowed_security_group_ids or ecs-service data_store_ingress."
  value       = aws_security_group.this.id
}

output "password_secret_arn" {
  description = "ARN of the secret holding the plain-string password. Pass this whole ARN as IMPEL_REDIS_PASSWORD; do not use a JSON-key suffix."
  value       = aws_secretsmanager_secret.password.arn
}

output "kms_key_arn" {
  description = "CMK encrypting the cluster at rest and the password secret."
  value       = aws_kms_key.this.arn
}
