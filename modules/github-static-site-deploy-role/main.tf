data "aws_caller_identity" "current" {}

locals {
  repository_owner = split("/", var.github_repository)[0]
  repository_name  = split("/", var.github_repository)[1]
  subject_prefix = var.github_oidc_ids == null ? "repo:${var.github_repository}" : format(
    "repo:%s@%d/%s@%d",
    local.repository_owner,
    var.github_oidc_ids.owner_id,
    local.repository_name,
    var.github_oidc_ids.repository_id,
  )
  oidc_subject = var.github_environment == null ? "${local.subject_prefix}:ref:refs/heads/${var.deploy_branch}" : "${local.subject_prefix}:environment:${replace(var.github_environment, ":", "%3A")}"
}

data "aws_iam_policy_document" "trust" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]
    principals {
      type        = "Federated"
      identifiers = ["arn:aws:iam::${data.aws_caller_identity.current.account_id}:oidc-provider/token.actions.githubusercontent.com"]
    }
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:sub"
      values   = [local.oidc_subject]
    }
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

data "aws_iam_policy_document" "deploy" {
  statement {
    effect    = "Allow"
    actions   = ["s3:ListBucket"]
    resources = [var.bucket_arn]
  }
  statement {
    effect    = "Allow"
    actions   = ["s3:PutObject", "s3:DeleteObject", "s3:AbortMultipartUpload"]
    resources = ["${var.bucket_arn}/*"]
  }
  statement {
    effect    = "Allow"
    actions   = ["cloudfront:CreateInvalidation"]
    resources = [var.distribution_arn]
  }
}

resource "aws_iam_role" "this" {
  name                 = var.name
  assume_role_policy   = data.aws_iam_policy_document.trust.json
  max_session_duration = 3600
}

resource "aws_iam_role_policy" "deploy" {
  name   = "deploy"
  role   = aws_iam_role.this.id
  policy = data.aws_iam_policy_document.deploy.json
}
