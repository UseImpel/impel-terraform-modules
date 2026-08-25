output "cluster_identifier" {
  description = "Identifier of the Aurora cluster."
  value       = aws_rds_cluster.this.cluster_identifier
}

output "cluster_arn" {
  description = "ARN of the cluster."
  value       = aws_rds_cluster.this.arn
}

output "endpoint" {
  description = "Writer endpoint hostname."
  value       = aws_rds_cluster.this.endpoint
}

output "reader_endpoint" {
  description = "Reader endpoint hostname. Resolves to the writer when reader_count is zero."
  value       = aws_rds_cluster.this.reader_endpoint
}

output "port" {
  description = "Port the cluster listens on."
  value       = aws_rds_cluster.this.port
}

output "database_name" {
  description = "Name of the initial database."
  value       = aws_rds_cluster.this.database_name
}

output "master_username" {
  description = "Master user name. The password lives in the secret at master_user_secret_arn."
  value       = aws_rds_cluster.this.master_username
}

output "master_user_secret_arn" {
  description = "ARN of the RDS-managed credentials secret. Pass secret-arn:password:: into a task definition to inject the password."
  value       = aws_rds_cluster.this.master_user_secret[0].secret_arn
}

output "security_group_id" {
  description = "Security group fronting the cluster. Grant client security groups ingress by passing them to allowed_security_group_ids."
  value       = aws_security_group.this.id
}

output "kms_key_arn" {
  description = "CMK encrypting storage, the credentials secret and Performance Insights."
  value       = aws_kms_key.this.arn
}
