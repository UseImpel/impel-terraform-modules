# acm-certificate

A DNS-validated ACM certificate for a load balancer, in an account whose DNS lives somewhere else.

## Creates

- `aws_acm_certificate` — and nothing else

Terraform requests the certificate and publishes the records that prove ownership. It does not
create those records, and it does not wait for validation.

## Call

```hcl
module "certificate" {
  source = "../../modules/acm-certificate"

  domain_name = "*.dev.example.com"
}
```

Covering the apex as well as its children needs both names, because a wildcard matches one label
only — `*.dev.example.com` matches `gateway.dev.example.com` but not `dev.example.com`:

```hcl
module "certificate" {
  source = "../../modules/acm-certificate"

  domain_name               = "*.dev.example.com"
  subject_alternative_names = ["dev.example.com"]
}
```

The certificate must live in the **same region as the load balancer**. ACM is regional for ELB;
only CloudFront reads certificates from `us-east-1`.

## Validating

```sh
terraform output -json validation_records
```

Create each record in the parent zone, then wait — issuance is usually 2–5 minutes once the record
resolves.

```sh
aws acm describe-certificate --certificate-arn <arn> --query 'Certificate.Status'
# → "ISSUED"
```

**At Cloudflare, validation records must be DNS-only (grey cloud).** A proxied record answers with
Cloudflare's own address rather than the value ACM is looking for, and validation never completes.

## Why there is no `aws_acm_certificate_validation`

That resource blocks the apply until the certificate reaches `ISSUED`, polling for up to 45 minutes.
It is the right resource when Terraform also owns the DNS zone: the records and the wait land in one
apply and the whole thing is automatic.

It is the wrong resource here. The parent zone is at Cloudflare, this repository has no Cloudflare
provider, and the records are added by hand — so the resource would block CI on something that
cannot happen until a human acts. The apply would sit for 45 minutes and then fail.

The trade is that nothing stops a caller attaching a certificate that is still `PENDING_VALIDATION`.
ELB rejects that outright, so the apply fails immediately with a message naming the certificate —
which is a better failure than a CI job idling for three quarters of an hour.

Wiring this to a zone Terraform does own would mean adding `aws_route53_record` and
`aws_acm_certificate_validation`, at which point the two-phase sequence collapses into one apply.

## Notes

`create_before_destroy` is set because replacing a certificate attached to a load balancer fails
otherwise: ELB will not release a certificate it is still serving.

The `status` output reflects the last read at plan time and goes stale between applies. Treat
`aws acm describe-certificate` as authoritative.
