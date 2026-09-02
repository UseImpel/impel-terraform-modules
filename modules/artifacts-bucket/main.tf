# Private, versioned SSE-KMS storage for code-intelligence artifacts, plus the
# artifact role services assume to mint presigned URLs.
#
# Only the prefixes named in var.lifecycle_rules expire by age; everything else
# is immutable content addressed by the application. The artifact role carries
# base authority over the whole bucket — every session that assumes it is
# narrowed to one exact prefix by the caller's inline session policy.

data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}

resource "aws_kms_key" "this" {
  #checkov:skip=CKV2_AWS_64:The default key policy grants the account root, which is what lets IAM policies govern access. A bespoke policy would have to re-grant the artifact role by hand.
  description             = "Encryption at rest for the ${var.name} artifacts bucket."
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
  #checkov:skip=CKV_AWS_18:CloudTrail data events cover artifact activity; logging to a second bucket would add another retention boundary.
  #checkov:skip=CKV_AWS_19:Encryption is configured in the companion aws_s3_bucket_server_side_encryption_configuration resource.
  #checkov:skip=CKV_AWS_21:Versioning is configured in the companion aws_s3_bucket_versioning resource.
  #checkov:skip=CKV_AWS_144:Cross-region replication is not part of the dev retention boundary.
  #checkov:skip=CKV_AWS_145:SSE-KMS is configured in the companion encryption resource.
  #checkov:skip=CKV2_AWS_62:This artifact store has no event consumer.
  bucket        = var.bucket_name
  force_destroy = var.force_destroy

  tags = {
    Name = var.bucket_name
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

  dynamic "rule" {
    for_each = { for lifecycle_rule in var.lifecycle_rules : lifecycle_rule.prefix => lifecycle_rule }

    content {
      id     = "expire-${trimsuffix(replace(rule.value.prefix, "/", "-"), "-")}"
      status = "Enabled"

      filter {
        prefix = rule.value.prefix
      }

      expiration {
        days = rule.value.expire_days
      }

      noncurrent_version_expiration {
        noncurrent_days = rule.value.expire_days
      }
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

# The artifact role is trusted by the account root, narrowed to the reader task
# roles by aws:PrincipalArn. This mirrors the CDK's AccountPrincipal +
# ArnLike composition and survives task-role recreation, which a direct
# role-principal trust would not.
data "aws_iam_policy_document" "artifact_trust" {
  statement {
    sid     = "AssumeFromReaderTaskRoles"
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "AWS"
      identifiers = ["arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.current.account_id}:root"]
    }

    condition {
      test     = "ArnLike"
      variable = "aws:PrincipalArn"
      values   = var.reader_task_role_arns
    }
  }
}

resource "aws_iam_role" "artifact" {
  name                 = var.name
  description          = "Base artifact authority; every session is further narrowed to one exact prefix."
  assume_role_policy   = data.aws_iam_policy_document.artifact_trust.json
  max_session_duration = 3600
}

data "aws_iam_policy_document" "artifact_access" {
  statement {
    sid    = "ListArtifactBucket"
    effect = "Allow"
    actions = [
      "s3:GetBucketLocation",
      "s3:ListBucket",
      "s3:ListBucketVersions",
      "s3:ListBucketMultipartUploads",
    ]
    resources = [aws_s3_bucket.this.arn]
  }

  statement {
    sid    = "ReadWriteArtifacts"
    effect = "Allow"
    actions = [
      "s3:GetObject",
      "s3:PutObject",
      "s3:AbortMultipartUpload",
      "s3:ListMultipartUploadParts",
      "s3:DeleteObject",
      "s3:DeleteObjectVersion",
    ]
    resources = ["${aws_s3_bucket.this.arn}/*"]
  }

  statement {
    sid       = "UseArtifactKey"
    effect    = "Allow"
    actions   = ["kms:Decrypt", "kms:DescribeKey", "kms:Encrypt", "kms:GenerateDataKey"]
    resources = [aws_kms_key.this.arn]
  }
}

resource "aws_iam_role_policy" "artifact" {
  name   = "${var.name}-objects"
  role   = aws_iam_role.artifact.id
  policy = data.aws_iam_policy_document.artifact_access.json
}

data "aws_iam_policy_document" "assume_artifact_role" {
  statement {
    sid       = "AssumeArtifactRole"
    effect    = "Allow"
    actions   = ["sts:AssumeRole"]
    resources = [aws_iam_role.artifact.arn]
  }
}

resource "aws_iam_policy" "assume_artifact_role" {
  name        = "${var.name}-assume"
  description = "Assume the ${var.name} artifact role to mint presigned artifact URLs."
  policy      = data.aws_iam_policy_document.assume_artifact_role.json
}
