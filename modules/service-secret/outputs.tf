output "secret_arn" {
  description = "ARN of the secret. Append :KEY:: to reference one key from an ECS task definition."
  value       = aws_secretsmanager_secret.this.arn
}

output "secret_name" {
  description = "Name of the secret, as passed to aws secretsmanager put-secret-value --secret-id."
  value       = aws_secretsmanager_secret.this.name
}

output "container_secrets" {
  description = "Map of key name to the secret-arn:KEY:: reference, ready to pass straight into the ecs-service module's container_secrets."
  value       = { for k in var.keys : k => "${aws_secretsmanager_secret.this.arn}:${k}::" }
}

output "expected_keys" {
  description = "Keys a task definition referencing this secret expects to exist. Every one must be present in the secret's JSON or the task fails to start with a ResourceNotFoundException."
  value       = var.keys
}

output "seed_command" {
  description = "Ready-to-run command that writes every expected key as an empty string, establishing the JSON shape. Run it once after create, then replace the values with real ones. Terraform never reads the contents back."
  value       = "aws secretsmanager put-secret-value --secret-id ${aws_secretsmanager_secret.this.name} --secret-string '${jsonencode({ for k in var.keys : k => "" })}'"
}
