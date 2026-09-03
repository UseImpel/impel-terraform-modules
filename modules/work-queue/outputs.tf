output "consumer_policy_arn" {
  description = "Customer-managed policy granting receive/delete on the queue and decrypt on the CMK. Attach to the worker's task role."
  value       = aws_iam_policy.consumer.arn
}

output "dlq_arn" {
  description = "ARN of the dead-letter queue."
  value       = aws_sqs_queue.dlq.arn
}

output "dlq_url" {
  description = "URL of the dead-letter queue."
  value       = aws_sqs_queue.dlq.url
}

output "kms_key_arn" {
  description = "ARN of the CMK encrypting both queues."
  value       = aws_kms_key.this.arn
}

output "producer_policy_arn" {
  description = "Customer-managed policy granting send on the queue and encrypt on the CMK. Attach to the submitter's task role."
  value       = aws_iam_policy.producer.arn
}

output "queue_arn" {
  description = "ARN of the work queue."
  value       = aws_sqs_queue.this.arn
}

output "queue_url" {
  description = "URL of the work queue. Pass to producers and consumers."
  value       = aws_sqs_queue.this.url
}
