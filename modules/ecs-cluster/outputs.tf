output "cluster_id" {
  description = "Cluster ID, which for ECS is the cluster ARN."
  value       = aws_ecs_cluster.this.id
}

output "cluster_arn" {
  description = "ARN of the cluster."
  value       = aws_ecs_cluster.this.arn
}

output "cluster_name" {
  description = "Name of the cluster, as passed to aws ecs describe-services --cluster."
  value       = aws_ecs_cluster.this.name
}
