output "instance_identifier" {
  description = "Identifier of the RDS instance."
  value       = aws_db_instance.this.identifier
}

output "instance_arn" {
  description = "ARN of the instance."
  value       = aws_db_instance.this.arn
}

# aws_db_instance exposes BOTH `address` (bare hostname) and `endpoint`
# (host:port). The aurora-serverless module's `endpoint` is the bare hostname,
# and every caller concatenates a port itself. Wiring `.endpoint` through here
# would append a second `:5432` to each PG_HOST, which fails as a DNS lookup at
# connect time rather than at plan time. `address` is the interchangeable one.
output "endpoint" {
  description = "Writer endpoint hostname, with no port. Matches the aurora-serverless module's endpoint output so a caller can swap between them."
  value       = aws_db_instance.this.address
}

output "endpoint_with_port" {
  description = "host:port form, for a caller that wants one string. Most do not: the port is a separate environment variable everywhere in this estate."
  value       = aws_db_instance.this.endpoint
}

output "port" {
  description = "Port the instance listens on."
  value       = aws_db_instance.this.port
}

output "database_name" {
  description = "Name of the initial database."
  value       = aws_db_instance.this.db_name
}

output "master_username" {
  description = "Master user name. The password lives in the secret at master_user_secret_arn."
  value       = aws_db_instance.this.username
}

output "master_user_secret_arn" {
  description = "ARN of the RDS-managed credentials secret. Pass secret-arn:password:: into a task definition to inject the password."
  value       = aws_db_instance.this.master_user_secret[0].secret_arn
}

output "security_group_id" {
  description = "Security group fronting the instance. Grant client security groups ingress by passing them to allowed_security_group_ids, or from the service side with the ecs-service module's data_store_ingress."
  value       = aws_security_group.this.id
}

output "kms_key_arn" {
  description = "CMK encrypting storage, the credentials secret and Performance Insights."
  value       = aws_kms_key.this.arn
}

output "master_password_rotation_days" {
  description = "Days between RDS-managed rotations of the master credential secret. Null means the RDS default of 7 is in force, because this module set no schedule."
  value       = var.master_password_rotation_days
}
