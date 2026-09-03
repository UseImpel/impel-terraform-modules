output "artifact_role_arn" {
  description = "ARN of the artifact role services assume to mint presigned URLs."
  value       = aws_iam_role.artifact.arn
}

output "artifact_role_name" {
  description = "Name of the artifact role, for session-policy construction."
  value       = aws_iam_role.artifact.name
}

output "assume_artifact_role_policy_arn" {
  description = "IAM policy granting sts:AssumeRole on the artifact role; attach to service task roles."
  value       = aws_iam_policy.assume_artifact_role.arn
}

output "bucket_arn" {
  description = "Artifacts bucket ARN."
  value       = aws_s3_bucket.this.arn
}

output "bucket_id" {
  description = "Artifacts bucket name."
  value       = aws_s3_bucket.this.id
}

output "kms_key_arn" {
  description = "CMK ARN used for artifact encryption."
  value       = aws_kms_key.this.arn
}
