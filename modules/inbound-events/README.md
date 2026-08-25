# inbound-events

SQS FIFO queue, dead-letter queue, overflow bucket, and one CMK — the Next
inbound-events plane. Shaped after prod Next `impel-next-sea-inbound-events.fifo`
in [`docs/prod-sea-mapping.md`](../../docs/prod-sea-mapping.md).

This is **not** interchangeable with [`app-bucket`](../app-bucket/). Overflow
objects share a CMK with the queue; the application encrypts S3 objects with
that same key (`IMPEL_INBOUND_EVENTS_KMS_KEY_ID`) and supplies FIFO
`MessageGroupId` / `MessageDeduplicationId` itself.

## Creates

- `aws_kms_key` with rotation, plus an alias named `alias/<name>`
- `aws_s3_bucket` (name from `bucket_name`) with public access blocked,
  `BucketOwnerEnforced`, versioning, SSE-KMS + bucket key, TLS-only
- Lifecycle: expire current objects at `object_retention_days`, noncurrent at
  `noncurrent_retention_days`, abort incomplete multipart uploads after 1 day,
  under `prefix/`
- FIFO queue `${name}.fifo` — per-message-group throughput, 7-day retention,
  60s visibility, 20s long poll, KMS encryption, redrive to the DLQ after 5
  receives
- FIFO DLQ `${name}-dlq.fifo` — 14-day retention, 5-minute visibility
- Queue policies denying non-TLS
- `aws_iam_policy` for send/receive on the **main queue only**, list/get/put/
  delete under `prefix/`, and encrypt/decrypt/generate-data-key on the CMK

Do not pass the task role into this module. The service reads `queue_url` and
`bucket_id`; attaching the policy here would cycle. Attach via
`ecs-service.task_role_policy_arns`.

## Call

```hcl
module "next_inbound" {
  source = "../../modules/inbound-events"

  name        = "impel-next-${var.environment}-inbound-events"
  bucket_name = "impel-next-${var.environment}-inbound-${data.aws_caller_identity.current.account_id}"
}
```

```hcl
environment_variables = {
  IMPEL_INBOUND_EVENTS_QUEUE_URL  = module.next_inbound.queue_url
  IMPEL_INBOUND_EVENTS_BUCKET     = module.next_inbound.bucket_id
  IMPEL_INBOUND_EVENTS_KMS_KEY_ID = module.next_inbound.kms_key_arn
}

task_role_policy_arns = [module.next_inbound.iam_policy_arn]
```

## Notes

`content_based_deduplication` is off because Next hashes the provider event id
into `MessageDeduplicationId`. Turning it on would ignore that id.

The DLQ is operational. The task role does not receive DLQ permissions; failed
messages are inspected by hand.

Terraform cannot take `prevent_destroy` as a variable. Do not destroy a prod
call of this module; `force_destroy` stays false so a destroy with objects in
the bucket fails.
