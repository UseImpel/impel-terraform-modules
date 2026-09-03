# Application Load Balancer: :80 redirects to :443, :443 terminates TLS and
# forwards to rules attached by callers. The default action is a fixed response
# rather than a forward so an unmatched host cannot reach an arbitrary service.

data "aws_caller_identity" "current" {}
data "aws_elb_service_account" "current" {}

locals {
  # Drives count/for_each on the listener and its ingress rules, so it must be
  # known at plan time. Inferring from certificate_arn breaks when the
  # certificate is created in the same apply and its ARN is still unknown --
  # enable_https lets the caller state it statically. Same reasoning as
  # attach_load_balancer in ../ecs-service.
  has_https           = var.enable_https != null ? var.enable_https : var.certificate_arn != null
  access_logs_enabled = var.enable_access_logs
  bucket_name         = "${var.name}-alb-${data.aws_caller_identity.current.account_id}"
}

resource "aws_security_group" "this" {
  name        = "${var.name}-alb"
  description = "Ingress to the ${var.name} load balancer."
  vpc_id      = var.vpc_id

  tags = {
    Name = "${var.name}-alb"
  }
}

resource "aws_vpc_security_group_ingress_rule" "http" {
  #checkov:skip=CKV_AWS_260:Port 80 exists only to redirect to 443. The source range is var.ingress_cidr_blocks; callers scope it (dev passes the VPC CIDR).
  for_each = toset(var.ingress_cidr_blocks)

  security_group_id = aws_security_group.this.id
  description       = "HTTP from ${each.value}; redirected to HTTPS by the listener."

  cidr_ipv4   = each.value
  from_port   = 80
  to_port     = 80
  ip_protocol = "tcp"
}

resource "aws_vpc_security_group_ingress_rule" "https" {
  for_each = local.has_https ? toset(var.ingress_cidr_blocks) : toset([])

  security_group_id = aws_security_group.this.id
  description       = "HTTPS from ${each.value}."

  cidr_ipv4   = each.value
  from_port   = 443
  to_port     = 443
  ip_protocol = "tcp"
}

# Targets register by IP across the private subnets on per-service ports. The
# task security groups are the control: each accepts traffic only from here.
# trivy:ignore:AWS-0104 Target IPs are allocated by ECS across the private subnets and their ports differ per service, so there is no stable destination to name. Each task security group admits this one alone.
resource "aws_vpc_security_group_egress_rule" "all" {
  security_group_id = aws_security_group.this.id
  description       = "Reach registered targets on their container ports."

  cidr_ipv4   = "0.0.0.0/0"
  ip_protocol = "-1"
}

# trivy:ignore:AWS-0053 This ALB is intentionally public for dev ingress; its security group only admits Cloudflare's published proxy ranges.
resource "aws_lb" "this" {
  #checkov:skip=CKV2_AWS_28:WAF association is the caller's decision; prod attaches a WebACL per ALB from CDK, dev deliberately runs without one.
  #checkov:skip=CKV_AWS_150:Deletion protection is var.enable_deletion_protection. Forcing it on would make a dev environment undestroyable.
  #checkov:skip=CKV2_AWS_20:The :80 listener does redirect to :443 whenever a certificate is supplied; the redirect lives in a dynamic block Checkov cannot follow.
  name               = var.name
  load_balancer_type = "application"
  internal           = var.internal
  subnets            = var.subnet_ids
  security_groups    = [aws_security_group.this.id]

  idle_timeout               = var.idle_timeout
  enable_deletion_protection = var.enable_deletion_protection
  drop_invalid_header_fields = var.drop_invalid_header_fields
  enable_http2               = true

  dynamic "access_logs" {
    for_each = local.access_logs_enabled ? [1] : []

    content {
      bucket  = aws_s3_bucket.access_logs[0].id
      enabled = true
    }
  }

  tags = {
    Name = var.name
  }

  depends_on = [aws_s3_bucket_policy.access_logs]
}

# Listeners

# Redirects when a certificate is present; otherwise serves the default
# response directly, leaving a certificate-less ALB usable for internal HTTP.
# trivy:ignore:AWS-0054 With certificate_arn set this listener only issues a 301 to :443. Plain HTTP is served solely when no certificate exists, which is the internal-ALB path — set certificate_arn to close it.
resource "aws_lb_listener" "http" {
  #checkov:skip=CKV_AWS_2:This listener exists to redirect to HTTPS. It only serves plain HTTP when no certificate is supplied, which is the internal-only path.
  #checkov:skip=CKV_AWS_103:TLS policy belongs to the HTTPS listener below; this one terminates nothing.
  load_balancer_arn = aws_lb.this.arn
  port              = 80
  protocol          = "HTTP"

  dynamic "default_action" {
    for_each = local.has_https ? [1] : []

    content {
      type = "redirect"

      redirect {
        protocol    = "HTTPS"
        port        = "443"
        host        = "#{host}"
        path        = "/#{path}"
        query       = "#{query}"
        status_code = "HTTP_301"
      }
    }
  }

  dynamic "default_action" {
    for_each = local.has_https ? [] : [1]

    content {
      type = "fixed-response"

      fixed_response {
        status_code  = tostring(var.default_fixed_response.status_code)
        content_type = var.default_fixed_response.content_type
        message_body = var.default_fixed_response.message_body
      }
    }
  }
}

resource "aws_lb_listener" "https" {
  #checkov:skip=CKV_AWS_103:False positive on the checkov 2.0.930 image CI pins. ssl_policy defaults to ELBSecurityPolicy-TLS13-1-2-2021-06, which is TLS 1.2 and 1.3; that version does not recognise TLS13 policy names.
  count = local.has_https ? 1 : 0

  load_balancer_arn = aws_lb.this.arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = var.ssl_policy
  certificate_arn   = var.certificate_arn

  lifecycle {
    precondition {
      condition     = var.certificate_arn != null
      error_message = "enable_https is true but certificate_arn is null: an HTTPS listener needs a certificate. Leave enable_https null to infer it from the ARN."
    }
  }

  # Callers attach forwarding rules; unmatched requests stop here.
  default_action {
    type = "fixed-response"

    fixed_response {
      status_code  = tostring(var.default_fixed_response.status_code)
      content_type = var.default_fixed_response.content_type
      message_body = var.default_fixed_response.message_body
    }
  }
}

resource "aws_lb_listener_certificate" "additional" {
  for_each = local.has_https ? toset(var.additional_certificate_arns) : toset([])

  listener_arn    = aws_lb_listener.https[0].arn
  certificate_arn = each.value
}

# Access logs

resource "aws_s3_bucket" "access_logs" {
  count = local.access_logs_enabled ? 1 : 0

  #checkov:skip=CKV_AWS_18:This is the access log bucket. Logging its own access would recurse; CloudTrail data events cover it.
  #checkov:skip=CKV_AWS_145:ELB log delivery supports SSE-S3 only. A CMK makes delivery fail silently, leaving a healthy load balancer and no logs.
  #checkov:skip=CKV_AWS_144:Access logs are regional operational data and are reproducible; cross-region replication is not worth the cost.
  #checkov:skip=CKV2_AWS_62:Event notifications have no consumer here.
  bucket        = local.bucket_name
  force_destroy = true
}

resource "aws_s3_bucket_public_access_block" "access_logs" {
  count = local.access_logs_enabled ? 1 : 0

  bucket = aws_s3_bucket.access_logs[0].id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_ownership_controls" "access_logs" {
  count = local.access_logs_enabled ? 1 : 0

  bucket = aws_s3_bucket.access_logs[0].id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_versioning" "access_logs" {
  count = local.access_logs_enabled ? 1 : 0

  bucket = aws_s3_bucket.access_logs[0].id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "access_logs" {
  count = local.access_logs_enabled ? 1 : 0

  bucket = aws_s3_bucket.access_logs[0].id

  rule {
    apply_server_side_encryption_by_default {
      # ELB log delivery supports SSE-S3 only. A CMK here fails silently: the
      # load balancer stays healthy and no logs arrive.
      sse_algorithm = "AES256"
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "access_logs" {
  count = local.access_logs_enabled ? 1 : 0

  bucket = aws_s3_bucket.access_logs[0].id

  rule {
    id     = "expire-access-logs"
    status = "Enabled"

    filter {}

    expiration {
      days = var.access_log_retention_days
    }

    noncurrent_version_expiration {
      noncurrent_days = 7
    }

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }
}

data "aws_iam_policy_document" "access_logs" {
  count = local.access_logs_enabled ? 1 : 0

  # Older regions write as a regional service account principal, newer ones as
  # logdelivery.elasticloadbalancing.amazonaws.com. Both are covered.
  statement {
    sid    = "ElbAccountWrite"
    effect = "Allow"

    principals {
      type        = "AWS"
      identifiers = [data.aws_elb_service_account.current.arn]
    }

    actions   = ["s3:PutObject"]
    resources = ["${aws_s3_bucket.access_logs[0].arn}/*"]
  }

  statement {
    sid    = "LogDeliveryWrite"
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["logdelivery.elasticloadbalancing.amazonaws.com"]
    }

    actions   = ["s3:PutObject"]
    resources = ["${aws_s3_bucket.access_logs[0].arn}/*"]
  }

  statement {
    sid    = "DenyInsecureTransport"
    effect = "Deny"

    principals {
      type        = "AWS"
      identifiers = ["*"]
    }

    actions = ["s3:*"]
    resources = [
      aws_s3_bucket.access_logs[0].arn,
      "${aws_s3_bucket.access_logs[0].arn}/*",
    ]

    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }
}

resource "aws_s3_bucket_policy" "access_logs" {
  count = local.access_logs_enabled ? 1 : 0

  bucket = aws_s3_bucket.access_logs[0].id
  policy = data.aws_iam_policy_document.access_logs[0].json

  depends_on = [aws_s3_bucket_public_access_block.access_logs]
}
