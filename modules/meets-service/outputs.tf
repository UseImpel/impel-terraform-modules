output "service_name" {
  description = "Name of the ECS service, as passed to aws ecs describe-services --services."
  value       = local.service.name
}

output "service_arn" {
  description = "ARN of the ECS service."
  value       = local.service.id
}

output "task_definition_arn" {
  description = "ARN of the current task definition revision."
  value       = aws_ecs_task_definition.this.arn
}

output "task_definition_family" {
  description = "Task definition family, stable across revisions."
  value       = aws_ecs_task_definition.this.family
}

output "task_security_group_id" {
  description = "Security group attached to the task. Pass this to efs-volume's allowed_security_group_id so the task can mount its volumes."
  value       = aws_security_group.task.id
}

output "task_role_arn" {
  description = "ARN of the task role — the runtime identity every container assumes."
  value       = aws_iam_role.task.arn
}

output "task_role_name" {
  description = "Name of the task role, for attaching further policies from the caller."
  value       = aws_iam_role.task.name
}

output "execution_role_arn" {
  description = "ARN of the task execution role used to pull images and read secrets."
  value       = aws_iam_role.execution.arn
}

output "target_group_arn" {
  description = "ARN of the target group, or null when the service has no load balancer."
  value       = one(aws_lb_target_group.this[*].arn)
}

output "target_group_arn_suffix" {
  description = "Target group ARN suffix, for CloudWatch dimensions."
  value       = one(aws_lb_target_group.this[*].arn_suffix)
}

output "log_group_name" {
  description = "CloudWatch log group receiving every container's output, one stream per container name."
  value       = aws_cloudwatch_log_group.this.name
}

output "container_names" {
  description = "Names of every container in the task definition, for building CloudWatch Logs Insights queries or aws ecs execute-command --container arguments."
  value       = keys(var.containers)
}
