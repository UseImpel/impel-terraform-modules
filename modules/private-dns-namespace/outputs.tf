output "namespace_id" {
  description = "ID of the private DNS namespace."
  value       = aws_service_discovery_private_dns_namespace.this.id
}

output "namespace_arn" {
  description = "ARN of the private DNS namespace."
  value       = aws_service_discovery_private_dns_namespace.this.arn
}

output "service_registry_arns" {
  description = "Service name to Cloud Map service ARN. Pass an entry to ecs-service's service_registry_arn to register that service's tasks under <service>.<namespace>."
  value       = { for k, s in aws_service_discovery_service.this : k => s.arn }
}
