output "bucket_id" {
  description = "Payload bucket name."
  value       = aws_s3_bucket.this.id
}

output "bucket_arn" {
  description = "Payload bucket ARN."
  value       = aws_s3_bucket.this.arn
}

output "kms_key_arn" {
  description = "CMK ARN used for payload encryption."
  value       = aws_kms_key.this.arn
}

output "iam_policy_arn" {
  description = "IAM policy granting the Sessions task payload access."
  value       = aws_iam_policy.access.arn
}
