# artifacts-bucket

Private, versioned SSE-KMS storage for immutable code-intelligence artifacts,
plus the artifact role services assume to mint presigned URLs.

SSE-KMS, not AES256. AES256 is required for ELB access-log delivery and is the
wrong default here — these objects are application artifacts (see
`modules/app-bucket/README.md` for the same rationale).

Only the prefixes named in `lifecycle_rules` expire by age; prefixes not listed
never expire — artifact metadata and explicit deletion are the authority for
live content. The artifact role carries base authority over the whole bucket;
per-tenant/per-prefix narrowing is not this module's job. Callers scope each
STS session with an inline session policy that restricts the assumed
credentials to one exact prefix.

## Creates

- `aws_kms_key` with rotation, plus an alias named `alias/<name>`
- `aws_s3_bucket` with public access blocked, `BucketOwnerEnforced`, versioning
- Bucket encryption using the CMK and a bucket key
- Bucket policy denying non-TLS
- Lifecycle: abort incomplete multipart uploads after 1 day, plus one
  current+noncurrent expiration rule per `lifecycle_rules` entry
- `aws_iam_role` (the artifact role) trusted by the account root, narrowed with
  an `ArnLike aws:PrincipalArn` condition to `reader_task_role_arns`, with a
  one-hour max session and an inline policy for object read/write/delete on the
  bucket and use of the CMK
- `aws_iam_policy` granting `sts:AssumeRole` on the artifact role, for
  attachment to service task roles

No access-logging bucket. CloudTrail data events cover object activity; logging
this bucket to another one recurses. No replication.

Terraform cannot take `prevent_destroy` as a variable. Do not destroy a prod
call of this module; `force_destroy` stays false so a destroy with objects in
the bucket fails.

## Call

```hcl
module "artifacts_bucket" {
  source = "../../modules/artifacts-bucket"

  name        = "impel-code-intelligence-dev-artifacts"
  bucket_name = "impel-code-intelligence-dev-${data.aws_caller_identity.current.account_id}"

  lifecycle_rules = [
    { prefix = "runtime/", expire_days = 1 },
  ]

  reader_task_role_arns = [
    "arn:aws:iam::123456789012:role/impel-code-intelligence-dev-api",
    "arn:aws:iam::123456789012:role/impel-code-intelligence-dev-query",
    "arn:aws:iam::123456789012:role/impel-code-intelligence-dev-worker",
  ]
}
```

Attach the assume policy on each service that mints presigned URLs:

```hcl
task_role_policy_arns = [module.artifacts_bucket.assume_artifact_role_policy_arn]
```

The trust policy uses the account-root principal plus `aws:PrincipalArn`
instead of naming the task roles as principals directly, so recreating a task
role does not sever the trust relationship.
