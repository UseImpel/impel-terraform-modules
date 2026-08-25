output "arn" {
  description = "ARN of the load balancer."
  value       = aws_lb.this.arn
}

output "arn_suffix" {
  description = "ARN suffix, used to build the ResourceLabel for ALBRequestCountPerTarget autoscaling policies and CloudWatch dimensions."
  value       = aws_lb.this.arn_suffix
}

output "dns_name" {
  description = "DNS name of the load balancer. Point a Route53 alias at this."
  value       = aws_lb.this.dns_name
}

output "zone_id" {
  description = "Hosted zone ID of the load balancer, required by a Route53 alias record."
  value       = aws_lb.this.zone_id
}

output "security_group_id" {
  description = "Security group of the load balancer. Task security groups accept ingress from this."
  value       = aws_security_group.this.id
}

output "https_listener_arn" {
  description = "ARN of the HTTPS listener, or null when no certificate was supplied. Attach forwarding rules here."
  value       = one(aws_lb_listener.https[*].arn)
}

output "http_listener_arn" {
  description = "ARN of the HTTP listener. Redirects to HTTPS when a certificate is present."
  value       = aws_lb_listener.http.arn
}

output "listener_arn" {
  description = "The listener callers should attach rules to: HTTPS when a certificate exists, HTTP otherwise."
  value       = local.has_https ? aws_lb_listener.https[0].arn : aws_lb_listener.http.arn
}

output "access_log_bucket" {
  description = "Name of the access log bucket, or null when access logging is disabled."
  value       = one(aws_s3_bucket.access_logs[*].id)
}
