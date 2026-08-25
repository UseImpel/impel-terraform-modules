output "bucket_id" {
  description = "Bucket name. Pass to the application as LOGS_S3_BUCKET (or the equivalent)."
  value       = aws_s3_bucket.this.id
}

output "bucket_arn" {
  description = "ARN of the bucket."
  value       = aws_s3_bucket.this.arn
}

output "kms_key_arn" {
  description = "ARN of the CMK encrypting objects. Extra grants, if any, target this."
  value       = aws_kms_key.this.arn
}

output "iam_policy_arn" {
  description = "Customer-managed policy granting object and CMK access. Attach to a task role this stack owns via ecs-service.task_role_policy_arns."
  value       = aws_iam_policy.access.arn
}
