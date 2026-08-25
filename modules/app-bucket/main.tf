# Private application bucket: CMK, TLS-only, versioned, lifecycle-expired.
# SSE-KMS rather than AES256 — callers put application payloads here, not ELB
# access logs (those still have to be SSE-S3). Access logging is omitted:
# CloudTrail data events cover the bucket, and logging it to another bucket
# recurses.

locals {
  prefix           = trimsuffix(var.prefix, "/")
  object_arn       = local.prefix == "" ? "${aws_s3_bucket.this.arn}/*" : "${aws_s3_bucket.this.arn}/${local.prefix}/*"
  list_prefixes    = local.prefix == "" ? ["*"] : [local.prefix, "${local.prefix}/*"]
  lifecycle_prefix = local.prefix == "" ? "" : "${local.prefix}/"
}

resource "aws_kms_key" "this" {
  #checkov:skip=CKV2_AWS_64:The default key policy grants the account root, which is what lets IAM policies govern access. A bespoke policy would have to re-grant every caller by hand.
  description             = "Encryption at rest for the ${var.name} bucket."
  enable_key_rotation     = true
  deletion_window_in_days = 30

  tags = {
    Name = "${var.name}-cmk"
  }
}

resource "aws_kms_alias" "this" {
  # Alias names allow hyphens and slashes, not dots. Bucket names may contain dots.
  name          = "alias/${replace(var.name, ".", "-")}"
  target_key_id = aws_kms_key.this.key_id
}

resource "aws_s3_bucket" "this" {
  #checkov:skip=CKV_AWS_18:This bucket holds application objects, not access logs. CloudTrail data events cover it; logging it to another bucket would recurse.
  #checkov:skip=CKV_AWS_19:False positive on the checkov 2.0.930 image CI pins. Encryption is aws_s3_bucket_server_side_encryption_configuration with aws:kms; that version does not follow the companion resource.
  #checkov:skip=CKV_AWS_21:False positive on the checkov 2.0.930 image CI pins. Versioning is aws_s3_bucket_versioning Enabled below.
  #checkov:skip=CKV_AWS_144:Objects expire with the application's retention and are reconstructable from the origin request; cross-region replication is not worth the cost.
  #checkov:skip=CKV_AWS_145:False positive on the checkov 2.0.930 image CI pins. SSE-KMS is set on the encryption configuration resource, not inline on the bucket.
  #checkov:skip=CKV2_AWS_62:Event notifications have no consumer here.
  bucket        = var.name
  force_destroy = var.force_destroy

  tags = {
    Name = var.name
  }
}

resource "aws_s3_bucket_public_access_block" "this" {
  bucket = aws_s3_bucket.this.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_ownership_controls" "this" {
  bucket = aws_s3_bucket.this.id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_versioning" "this" {
  bucket = aws_s3_bucket.this.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "this" {
  bucket = aws_s3_bucket.this.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.this.arn
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "this" {
  bucket = aws_s3_bucket.this.id

  depends_on = [aws_s3_bucket_versioning.this]

  rule {
    id     = "expire-objects"
    status = "Enabled"

    filter {
      prefix = local.lifecycle_prefix
    }

    expiration {
      days = var.retention_days
    }

    noncurrent_version_expiration {
      noncurrent_days = var.retention_days
    }

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }
}

data "aws_iam_policy_document" "bucket" {
  statement {
    sid    = "DenyInsecureTransport"
    effect = "Deny"

    principals {
      type        = "AWS"
      identifiers = ["*"]
    }

    actions = ["s3:*"]
    resources = [
      aws_s3_bucket.this.arn,
      "${aws_s3_bucket.this.arn}/*",
    ]

    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }
}

resource "aws_s3_bucket_policy" "this" {
  bucket = aws_s3_bucket.this.id
  policy = data.aws_iam_policy_document.bucket.json

  depends_on = [aws_s3_bucket_public_access_block.this]
}

data "aws_iam_policy_document" "access" {
  statement {
    sid    = "ListPrefix"
    effect = "Allow"
    actions = [
      "s3:ListBucket",
      "s3:GetBucketLocation",
      "s3:ListBucketMultipartUploads",
    ]
    resources = [aws_s3_bucket.this.arn]

    condition {
      test     = "StringLike"
      variable = "s3:prefix"
      values   = local.list_prefixes
    }
  }

  statement {
    sid    = "ObjectReadWrite"
    effect = "Allow"
    actions = [
      "s3:GetObject",
      "s3:PutObject",
      "s3:DeleteObject",
      "s3:AbortMultipartUpload",
      "s3:ListMultipartUploadParts",
      "s3:GetObjectTagging",
      "s3:PutObjectTagging",
    ]
    resources = [local.object_arn]
  }

  statement {
    sid    = "KmsForBucket"
    effect = "Allow"
    actions = [
      "kms:Decrypt",
      "kms:DescribeKey",
      "kms:GenerateDataKey",
    ]
    resources = [aws_kms_key.this.arn]
  }
}

resource "aws_iam_policy" "access" {
  name        = "${var.name}-objects"
  description = "Read and write objects in ${var.name} under the configured prefix, and use its CMK."
  policy      = data.aws_iam_policy_document.access.json
}

resource "aws_iam_role_policy_attachment" "access" {
  for_each = toset(var.iam_role_names)

  role       = each.value
  policy_arn = aws_iam_policy.access.arn
}
