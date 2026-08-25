# A DNS-validated ACM certificate. The module creates the certificate and
# publishes the records that prove ownership; it does not create those records
# and does not wait for them to appear.
#
# That split is deliberate. aws_acm_certificate_validation blocks an apply until
# the certificate reaches ISSUED, polling for up to 45 minutes. It is the right
# resource when Terraform also owns the DNS zone, because both halves land in
# one apply. Here the parent zone is at Cloudflare and this repository has no
# Cloudflare provider, so the validation records are added by hand — including
# the validation resource would hang the apply-dev job on a record that cannot
# appear until a human acts.
#
# The consequence is that a caller can attach a still-pending certificate to a
# load balancer. ELB rejects that outright, so the failure is immediate and
# names the cause, which is a better outcome than a CI job idling for 45
# minutes. See validation_records in outputs.tf for what to publish.

resource "aws_acm_certificate" "this" {
  #checkov:skip=CKV2_AWS_71:A wildcard is the caller's decision, and callers pass one deliberately: naming each host instead would mean a validation record per service, hand-created at Cloudflare, and a certificate replacement every time a service is added. The blast radius is bounded by the label depth -- *.dev.useimpel.com cannot be presented for anything outside dev.
  domain_name               = var.domain_name
  subject_alternative_names = var.subject_alternative_names
  validation_method         = "DNS"

  # Replacing a certificate in use by a load balancer fails unless the
  # replacement exists first: ELB will not release a certificate it is still
  # serving.
  lifecycle {
    create_before_destroy = true
  }

  # AWS tag values accept [\p{L}\p{Z}\p{N}_.:/=+\-@] only, which excludes the
  # asterisk in a wildcard name -- RequestCertificate rejects the whole call
  # with a ValidationException naming the tag index rather than the character.
  # terraform plan does not check tag values against the API, so this only
  # surfaces on apply. "star." is the conventional stand-in.
  tags = {
    Name = replace(var.domain_name, "*", "star")
  }
}
