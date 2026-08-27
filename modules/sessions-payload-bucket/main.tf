# Private, versioned payload storage for impel-sessions.
#
# Current batch objects are intentionally not expired by age: metadata retention
# and explicit deletion are the authority for live payloads. The only lifecycle
# rule here aborts abandoned multipart uploads.

locals {
  object_arn  = "${aws_s3_bucket.this.arn}/${trimsuffix(var.prefix, "/")}/*"
  list_prefix = trimsuffix(var.prefix, "/")
}

resource "aws_kms_key" "this" {
  #checkov:skip=CKV2_AWS_64:The default key policy grants the account root, which is what lets IAM policies govern access. A bespoke policy would have to re-grant the task role by hand.
  description             = "Encryption at rest for the ${var.name} Sessions payload bucket."
  enable_key_rotation     = true
  deletion_window_in_days = 30

  tags = {
    Name = "${var.name}-cmk"
  }
}

resource "aws_kms_alias" "this" {
  name          = "alias/${replace(var.name, ".", "-")}"
  target_key_id = aws_kms_key.this.key_id
}

resource "aws_s3_bucket" "this" {
  #checkov:skip=CKV_AWS_18:CloudTrail data events cover application payload activity; logging to a second bucket would add another retention boundary.
  #checkov:skip=CKV_AWS_19:Encryption is configured in the companion aws_s3_bucket_server_side_encryption_configuration resource.
  #checkov:skip=CKV_AWS_21:Versioning is configured in the companion aws_s3_bucket_versioning resource.
  #checkov:skip=CKV_AWS_144:Cross-region replication is not part of the dev retention boundary.
  #checkov:skip=CKV_AWS_145:SSE-KMS is configured in the companion encryption resource.
  #checkov:skip=CKV2_AWS_62:This immutable object store has no event consumer.
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
    id     = "abort-incomplete-multipart-uploads"
    status = "Enabled"

    filter {}

    abort_incomplete_multipart_upload {
      days_after_initiation = 1
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
    sid       = "ListPayloadPrefix"
    effect    = "Allow"
    actions   = ["s3:ListBucket", "s3:GetBucketLocation", "s3:ListBucketMultipartUploads"]
    resources = [aws_s3_bucket.this.arn]

    condition {
      test     = "StringLike"
      variable = "s3:prefix"
      values   = [local.list_prefix, "${local.list_prefix}/*"]
    }
  }

  statement {
    sid    = "ReadWritePayloads"
    effect = "Allow"
    actions = [
      "s3:AbortMultipartUpload",
      "s3:DeleteObject",
      "s3:GetObject",
      "s3:ListMultipartUploadParts",
      "s3:PutObject",
    ]
    resources = [local.object_arn]
  }

  statement {
    sid       = "UsePayloadKey"
    effect    = "Allow"
    actions   = ["kms:Decrypt", "kms:DescribeKey", "kms:Encrypt", "kms:GenerateDataKey"]
    resources = [aws_kms_key.this.arn]
  }
}

resource "aws_iam_policy" "access" {
  name        = "${var.name}-objects"
  description = "Read and write Sessions payloads under ${var.prefix}, and use their CMK."
  policy      = data.aws_iam_policy_document.access.json
}
