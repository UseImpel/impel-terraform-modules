output "file_system_id" {
  description = "Filesystem id, e.g. fs-0123456789abcdef0. Pass to a task definition's volume.efsVolumeConfiguration.fileSystemId."
  value       = aws_efs_file_system.this.id
}

output "file_system_arn" {
  description = "ARN of the filesystem."
  value       = aws_efs_file_system.this.arn
}

output "access_point_ids" {
  description = "Access point id per key in var.access_points, e.g. { postgres-data = \"fsap-...\" }. Pass into a task definition's volume.efsVolumeConfiguration.authorizationConfig.accessPointId."
  value       = { for key, ap in aws_efs_access_point.this : key => ap.id }
}

output "access_point_arns" {
  description = "Access point ARN per key in var.access_points."
  value       = { for key, ap in aws_efs_access_point.this : key => ap.arn }
}

output "security_group_id" {
  description = "Security group fronting the filesystem. Grant additional client security groups ingress by adding an ingress rule against this id from the caller side."
  value       = aws_security_group.this.id
}
