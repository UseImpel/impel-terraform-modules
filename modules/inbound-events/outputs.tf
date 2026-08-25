output "queue_url" {
  description = "URL of the FIFO queue. Pass to the application as IMPEL_INBOUND_EVENTS_QUEUE_URL."
  value       = aws_sqs_queue.this.url
}

output "queue_arn" {
  description = "ARN of the FIFO queue."
  value       = aws_sqs_queue.this.arn
}

output "bucket_id" {
  description = "Overflow bucket name. Pass to the application as IMPEL_INBOUND_EVENTS_BUCKET."
  value       = aws_s3_bucket.this.id
}

output "kms_key_arn" {
  description = "ARN of the CMK encrypting the queue and overflow objects. Pass to the application as IMPEL_INBOUND_EVENTS_KMS_KEY_ID."
  value       = aws_kms_key.this.arn
}

output "iam_policy_arn" {
  description = "Customer-managed policy granting queue, overflow-object and CMK access. Attach to a task role this stack owns via ecs-service.task_role_policy_arns."
  value       = aws_iam_policy.access.arn
}
