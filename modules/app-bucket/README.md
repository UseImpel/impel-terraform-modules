# app-bucket

A private application bucket with its own CMK, TLS-only access, versioning, and a
lifecycle that expires objects (or, with `retention_days = null`, keeps them).
The module also publishes a customer-managed IAM policy for the application role
that reads and writes under a prefix.

SSE-KMS, not AES256. AES256 is required for ELB access-log delivery and is the
wrong default here — these objects are application payloads (prompts, responses).

## Creates

- `aws_kms_key` with rotation, plus an alias named `alias/<name>`
- `aws_s3_bucket` with public access blocked, `BucketOwnerEnforced`, versioning
- Bucket encryption using the CMK and a bucket key
- Bucket policy denying non-TLS
- Lifecycle: expire current and noncurrent objects at `retention_days`, abort
  incomplete multipart uploads after 7 days. `retention_days = null` keeps
  every object and noncurrent version forever; the rule (same id,
  `expire-objects`) then only aborts incomplete multipart uploads
- `aws_iam_policy` for list/get/put/delete (and tagging) under `prefix`, plus
  `kms:Decrypt` / `kms:GenerateDataKey` / `kms:DescribeKey` on the CMK
- Optional attachments of that policy to `iam_role_names`

No access-logging bucket. CloudTrail data events cover object activity; logging
this bucket to another one recurses. No replication.

Terraform cannot take `prevent_destroy` as a variable. Do not destroy a prod
call of this module; `force_destroy` stays false so a destroy with objects in
the bucket fails.

## Call

```hcl
module "gateway_log_bucket" {
  source = "../../modules/app-bucket"

  name           = "impel-gateway-${var.environment}-bifrost-logs-${data.aws_caller_identity.current.account_id}"
  prefix         = "bifrost/logs"
  retention_days = 14
}
```

To keep objects forever (for example, logs the application never deletes),
pass `retention_days = null`. Switching an existing bucket from a number to
`null` is an in-place update of the lifecycle configuration that removes only
the `expiration` and `noncurrent_version_expiration` actions. The default stays
14 days, so callers that do not set it plan no change.

When this stack owns the task role, attach the policy on the service:

```hcl
task_role_policy_arns = [module.gateway_log_bucket.iam_policy_arn]
```

When the task role already exists (a CDK service), pass its name in:

```hcl
iam_role_names = [local.gateway_task_role_name]
```

Do not pass a Terraform-managed task role into `iam_role_names` while that
service also reads `bucket_id` — that is a cycle. Attach via
`task_role_policy_arns` instead.
