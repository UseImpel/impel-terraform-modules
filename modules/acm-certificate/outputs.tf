output "arn" {
  description = "ARN of the certificate. Pass to the alb module's certificate_arn. Attaching it before validation completes fails: ELB rejects a certificate that is not ISSUED."
  value       = aws_acm_certificate.this.arn
}

output "domain_name" {
  description = "Primary domain the certificate was issued for."
  value       = aws_acm_certificate.this.domain_name
}

output "status" {
  description = "Certificate status, PENDING_VALIDATION until the records below are published and ACM has seen them. Stale between applies; aws acm describe-certificate is authoritative."
  value       = aws_acm_certificate.this.status
}

# ACM emits one option per distinct name, and a wildcard validates against the
# same record as its apex, so identical entries are collapsed by keying on the
# record name rather than the domain.
output "validation_records" {
  description = "DNS records proving domain ownership, keyed by record name. Create each in the parent zone before the certificate can be attached to anything. At Cloudflare these must be DNS-only: a proxied record returns Cloudflare's address instead of the value ACM is looking for, and validation never completes."
  value = {
    for o in aws_acm_certificate.this.domain_validation_options :
    o.resource_record_name => {
      name  = o.resource_record_name
      type  = o.resource_record_type
      value = o.resource_record_value
    }
  }
}
