# Next inbound-events plane: SQS FIFO + overflow S3, one CMK for both.
# Shaped after prod CDK ImpelNextSea DataStack (inbound queue, DLQ, overflow
# bucket, data key). The application supplies MessageGroupId and
# MessageDeduplicationId; payloads over ~240 KB land under prefix/.

locals {
  object_arn       = "${aws_s3_bucket.this.arn}/${var.prefix}/*"
  lifecycle_prefix = "${var.prefix}/"
}

resource "aws_kms_key" "this" {
  #checkov:skip=CKV2_AWS_64:The default key policy grants the account root, which is what lets IAM policies govern access. A bespoke policy would have to re-grant SQS, S3 and the task role by hand.
  description             = "Encryption at rest for ${var.name} SQS and overflow objects."
  enable_key_rotation     = true
  deletion_window_in_days = 30

  tags = {
    Name = var.name
  }
}

resource "aws_kms_alias" "this" {
  name          = "alias/${var.name}"
  target_key_id = aws_kms_key.this.key_id
}

resource "aws_s3_bucket" "this" {
  #checkov:skip=CKV_AWS_18:This bucket holds transient overflow payloads, not access logs. CloudTrail data events cover it; logging it to another bucket would recurse.
  #checkov:skip=CKV_AWS_19:False positive on the checkov 2.0.930 image CI pins. Encryption is aws_s3_bucket_server_side_encryption_configuration with aws:kms; that version does not follow the companion resource.
  #checkov:skip=CKV_AWS_21:False positive on the checkov 2.0.930 image CI pins. Versioning is aws_s3_bucket_versioning Enabled below.
  #checkov:skip=CKV_AWS_144:Objects expire with the application's retention and are reconstructable from the origin webhook; cross-region replication is not worth the cost.
  #checkov:skip=CKV_AWS_145:False positive on the checkov 2.0.930 image CI pins. SSE-KMS is set on the encryption configuration resource, not inline on the bucket.
  #checkov:skip=CKV2_AWS_62:Event notifications have no consumer here; the SQS consumer is the application.
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
    id     = "expire-transient-inbound-events"
    status = "Enabled"

    filter {
      prefix = local.lifecycle_prefix
    }

    expiration {
      days = var.object_retention_days
    }

    noncurrent_version_expiration {
      noncurrent_days = var.noncurrent_retention_days
    }

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

resource "aws_sqs_queue" "dlq" {
  #checkov:skip=CKV_AWS_27:False positive on the checkov 2.0.930 image CI pins. kms_master_key_id is set; that version does not follow it.
  #checkov:skip=CKV2_AWS_73:False positive on the checkov 2.0.930 image CI pins. Encryption is customer-managed KMS, not SQS-managed SSE.
  #checkov:skip=CKV2_AWS_3:This queue is the dead-letter destination; it has no further redrive.
  name                        = "${var.name}-dlq.fifo"
  fifo_queue                  = true
  content_based_deduplication = false
  kms_master_key_id           = aws_kms_key.this.arn
  message_retention_seconds   = 1209600
  visibility_timeout_seconds  = 300

  tags = {
    Name = "${var.name}-dlq"
  }
}

resource "aws_sqs_queue" "this" {
  #checkov:skip=CKV_AWS_27:False positive on the checkov 2.0.930 image CI pins. kms_master_key_id is set; that version does not follow it.
  #checkov:skip=CKV2_AWS_73:False positive on the checkov 2.0.930 image CI pins. Encryption is customer-managed KMS, not SQS-managed SSE.
  name                        = "${var.name}.fifo"
  fifo_queue                  = true
  content_based_deduplication = false
  deduplication_scope         = "messageGroup"
  fifo_throughput_limit       = "perMessageGroupId"
  kms_master_key_id           = aws_kms_key.this.arn
  message_retention_seconds   = 604800
  visibility_timeout_seconds  = 60
  receive_wait_time_seconds   = 20

  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.dlq.arn
    maxReceiveCount     = 5
  })

  tags = {
    Name = var.name
  }
}

data "aws_iam_policy_document" "queue_ssl" {
  statement {
    sid    = "DenyInsecureTransport"
    effect = "Deny"

    principals {
      type        = "AWS"
      identifiers = ["*"]
    }

    actions   = ["sqs:*"]
    resources = [aws_sqs_queue.this.arn]

    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }
}

data "aws_iam_policy_document" "dlq_ssl" {
  statement {
    sid    = "DenyInsecureTransport"
    effect = "Deny"

    principals {
      type        = "AWS"
      identifiers = ["*"]
    }

    actions   = ["sqs:*"]
    resources = [aws_sqs_queue.dlq.arn]

    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }
}

resource "aws_sqs_queue_policy" "this" {
  queue_url = aws_sqs_queue.this.id
  policy    = data.aws_iam_policy_document.queue_ssl.json
}

resource "aws_sqs_queue_policy" "dlq" {
  queue_url = aws_sqs_queue.dlq.id
  policy    = data.aws_iam_policy_document.dlq_ssl.json
}

# Task-role permissions match prod Next runtime-stack.ts: the main queue, the
# overflow prefix, and this CMK. The DLQ is operational, not application-facing.
data "aws_iam_policy_document" "access" {
  statement {
    sid    = "InboundQueue"
    effect = "Allow"
    actions = [
      "sqs:ChangeMessageVisibility",
      "sqs:DeleteMessage",
      "sqs:GetQueueAttributes",
      "sqs:GetQueueUrl",
      "sqs:ReceiveMessage",
      "sqs:SendMessage",
    ]
    resources = [aws_sqs_queue.this.arn]
  }

  statement {
    sid    = "OverflowBucket"
    effect = "Allow"
    actions = [
      "s3:GetBucketLocation",
      "s3:ListBucket",
    ]
    resources = [aws_s3_bucket.this.arn]
  }

  statement {
    sid    = "OverflowObjects"
    effect = "Allow"
    actions = [
      "s3:DeleteObject",
      "s3:GetObject",
      "s3:PutObject",
    ]
    resources = [local.object_arn]
  }

  statement {
    sid    = "InboundKms"
    effect = "Allow"
    actions = [
      "kms:Decrypt",
      "kms:DescribeKey",
      "kms:Encrypt",
      "kms:GenerateDataKey",
    ]
    resources = [aws_kms_key.this.arn]
  }
}

resource "aws_iam_policy" "access" {
  name        = "${var.name}-access"
  description = "Send and receive on ${var.name}.fifo, read and write overflow objects, and use the inbound CMK."
  policy      = data.aws_iam_policy_document.access.json
}
