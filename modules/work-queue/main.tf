# Standard (non-FIFO) SQS work queue with DLQ, encrypted with one CMK.
# Shaped after inbound-events minus the overflow bucket and FIFO arguments:
# a plain work queue for asynchronous jobs, with separate consumer and
# producer IAM policies so each side gets only what it needs.

resource "aws_kms_key" "this" {
  #checkov:skip=CKV2_AWS_64:The default key policy grants the account root, which is what lets IAM policies govern access. A bespoke policy would have to re-grant SQS and the task roles by hand.
  description             = "Encryption at rest for the ${var.name} SQS work queue and its DLQ."
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

resource "aws_sqs_queue" "dlq" {
  #checkov:skip=CKV_AWS_27:False positive on the checkov 2.0.930 image CI pins. kms_master_key_id is set; that version does not follow it.
  #checkov:skip=CKV2_AWS_73:False positive on the checkov 2.0.930 image CI pins. Encryption is customer-managed KMS, not SQS-managed SSE.
  #checkov:skip=CKV2_AWS_3:This queue is the dead-letter destination; it has no further redrive.
  name                       = "${var.name}-dlq"
  kms_master_key_id          = aws_kms_key.this.arn
  message_retention_seconds  = 1209600
  visibility_timeout_seconds = 300

  tags = {
    Name = "${var.name}-dlq"
  }
}

resource "aws_sqs_queue" "this" {
  #checkov:skip=CKV_AWS_27:False positive on the checkov 2.0.930 image CI pins. kms_master_key_id is set; that version does not follow it.
  #checkov:skip=CKV2_AWS_73:False positive on the checkov 2.0.930 image CI pins. Encryption is customer-managed KMS, not SQS-managed SSE.
  name                       = var.name
  kms_master_key_id          = aws_kms_key.this.arn
  message_retention_seconds  = var.message_retention_seconds
  visibility_timeout_seconds = var.visibility_timeout_seconds
  receive_wait_time_seconds  = 20

  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.dlq.arn
    maxReceiveCount     = var.max_receive_count
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

# Consumer and producer are separate policies so a worker cannot enqueue and a
# submitter cannot drain. Both cover the main queue only; the DLQ is
# operational, not application-facing.
data "aws_iam_policy_document" "consumer" {
  statement {
    sid    = "WorkQueueConsume"
    effect = "Allow"
    actions = [
      "sqs:ChangeMessageVisibility",
      "sqs:DeleteMessage",
      "sqs:GetQueueAttributes",
      "sqs:GetQueueUrl",
      "sqs:ReceiveMessage",
    ]
    resources = [aws_sqs_queue.this.arn]
  }

  statement {
    sid    = "WorkQueueConsumeKms"
    effect = "Allow"
    actions = [
      "kms:Decrypt",
      "kms:DescribeKey",
    ]
    resources = [aws_kms_key.this.arn]
  }
}

data "aws_iam_policy_document" "producer" {
  statement {
    sid    = "WorkQueueProduce"
    effect = "Allow"
    actions = [
      "sqs:GetQueueAttributes",
      "sqs:GetQueueUrl",
      "sqs:SendMessage",
    ]
    resources = [aws_sqs_queue.this.arn]
  }

  statement {
    sid    = "WorkQueueProduceKms"
    effect = "Allow"
    actions = [
      "kms:Encrypt",
      "kms:GenerateDataKey",
    ]
    resources = [aws_kms_key.this.arn]
  }
}

resource "aws_iam_policy" "consumer" {
  name        = "${var.name}-consumer"
  description = "Receive and delete on ${var.name} and decrypt with its CMK."
  policy      = data.aws_iam_policy_document.consumer.json
}

resource "aws_iam_policy" "producer" {
  name        = "${var.name}-producer"
  description = "Send on ${var.name} and encrypt with its CMK."
  policy      = data.aws_iam_policy_document.producer.json
}
