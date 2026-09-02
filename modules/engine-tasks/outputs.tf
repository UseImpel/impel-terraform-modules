output "task_definition_arns" {
  description = "Engine name to revision-pinned task definition ARN. jsonencode() this map for CODE_INTELLIGENCE_AWS_TASK_DEFINITIONS_JSON; add aliases (e.g. ast-grep = toolbox's ARN) at the call site."
  value       = { for k, td in aws_ecs_task_definition.this : k => td.arn }
}

output "families" {
  description = "Engine name to task definition family. Naming a family in run-task resolves to its latest ACTIVE revision."
  value       = local.families
}

output "checkout_security_group_id" {
  description = "Open-egress security group for checkout tasks. Passed by the services as CODE_INTELLIGENCE_AWS_CHECKOUT_SECURITY_GROUP_IDS."
  value       = aws_security_group.checkout.id
}

output "engine_security_group_id" {
  description = "Sealed security group for index/query engine tasks (DNS, interface endpoints and S3 gateway only). Passed by the services as CODE_INTELLIGENCE_AWS_ECS_SECURITY_GROUP_IDS."
  value       = aws_security_group.engine.id
}

output "worker_runtask_policy_arn" {
  description = "Policy letting the worker service RunTask every engine family (checkout included) as checkout/index. Attach via ecs-service task_role_policy_arns."
  value       = aws_iam_policy.runtask["worker"].arn
}

output "query_runtask_policy_arn" {
  description = "Policy letting the query service RunTask the non-checkout engine families as query. Attach via ecs-service task_role_policy_arns."
  value       = aws_iam_policy.runtask["query"].arn
}

output "execution_role_arn" {
  description = "Shared fleet execution role (ECR pull + engine log group writes). Also a PassRole target in both RunTask policies."
  value       = aws_iam_role.execution.arn
}

output "task_role_arn" {
  description = "Shared credential-free fleet task role. Carries no policies by design; a PassRole target in both RunTask policies."
  value       = aws_iam_role.task.arn
}

output "log_group_name" {
  description = "Shared CloudWatch log group all engine tasks write to, one stream prefix per engine."
  value       = aws_cloudwatch_log_group.engine.name
}
