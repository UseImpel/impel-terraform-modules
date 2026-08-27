# sessions-payload-bucket

Private, versioned SSE-KMS storage for `impel-sessions` payload batches.

The module deliberately does **not** expire current objects by age. Sessions
metadata, not an S3 lifecycle clock, is the authority for live batches. It
only aborts incomplete multipart uploads after one day. The application task receives a policy restricted to
the configured key prefix and the bucket's CMK.

```hcl
module "sessions_payload_bucket" {
  source = "../../modules/sessions-payload-bucket"

  name   = "impel-sessions-dev-payload-867264375510"
  prefix = "orgs"
}
```
