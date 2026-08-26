output "family" {
  description = "Task definition family. Pass to aws ecs run-task --task-definition; naming the family resolves to the latest ACTIVE revision."
  value       = aws_ecs_task_definition.this.family
}

output "task_definition_arn" {
  description = "ARN of the current bootstrap task definition revision."
  value       = aws_ecs_task_definition.this.arn
}
