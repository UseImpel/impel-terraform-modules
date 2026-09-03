# work-queue

Standard (non-FIFO) SQS work queue, dead-letter queue, and one CMK. Built for
the code-intelligence dev port; reusable anywhere a plain asynchronous job
queue is needed.

This is **not** [`inbound-events`](../inbound-events/): no overflow bucket, no
FIFO ordering or deduplication — messages may arrive out of order and more
than once, so consumers must be idempotent. Payloads must fit the 256 KB SQS
limit.

## Creates

- `aws_kms_key` with rotation, plus an alias named `alias/<name>`
- Queue `${name}` — KMS encryption, 20s long poll,
  `visibility_timeout_seconds` (default 120s), retention
  `message_retention_seconds` (default 14 days), redrive to the DLQ after
  `max_receive_count` receives (default 8)
- DLQ `${name}-dlq` — 14-day retention, 5-minute visibility
- Queue policies denying non-TLS
- `aws_iam_policy` **consumer** — receive/delete/get-attributes on the main
  queue and decrypt on the CMK
- `aws_iam_policy` **producer** — send/get-attributes on the main queue and
  encrypt/generate-data-key on the CMK

The DLQ is operational, not application-facing. Neither policy grants DLQ
access; failed messages are inspected by hand.

## Call

```hcl
module "work_queue" {
  source = "../../modules/work-queue"

  name = "impel-code-intelligence-${var.environment}-work"
}
```

```hcl
environment_variables = {
  IMPEL_WORK_QUEUE_URL = module.work_queue.queue_url
}

task_role_policy_arns = [
  module.work_queue.consumer_policy_arn,
  module.work_queue.producer_policy_arn,
]
```

Attach `consumer_policy_arn` to workers and `producer_policy_arn` to
submitters; a service that does both attaches both. Do not pass the task role
into this module — attaching here would cycle with the service reading
`queue_url`.
