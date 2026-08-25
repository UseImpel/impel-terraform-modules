# One ECR repository plus its lifecycle and cross-account pull policy.

locals {
  has_untagged_rule = var.untagged_image_expiry_days > 0
  has_tagged_rule   = var.max_tagged_images > 0

  # Rules are numbered from 1 with no gaps; untagged is evaluated first.
  #
  # The two rule shapes are built as separate JSON fragments and spliced
  # together rather than concat()-ed into one list. concat unifies its
  # arguments to a common object type, and because the untagged rule carries
  # countUnit = "days" that unification rewrites every value as a string —
  # countNumber 20 becomes "20". ECR accepts it, but the policy no longer
  # matches a console- or CDK-authored one, so adopting an existing repository
  # shows a spurious diff that forces replacement.
  untagged_rule_json = local.has_untagged_rule ? jsonencode({
    rulePriority = 1
    selection = {
      tagStatus   = "untagged"
      countType   = "sinceImagePushed"
      countUnit   = "days"
      countNumber = var.untagged_image_expiry_days
    }
    action = { type = "expire" }
  }) : ""

  tagged_rule_json = local.has_tagged_rule ? jsonencode({
    rulePriority = local.has_untagged_rule ? 2 : 1
    selection = {
      tagStatus   = "any"
      countType   = "imageCountMoreThan"
      countNumber = var.max_tagged_images
    }
    action = { type = "expire" }
  }) : ""

  lifecycle_rule_json = compact([local.untagged_rule_json, local.tagged_rule_json])

  # Assembled as a string for the same reason: passing the decoded objects back
  # through a list would re-unify their types.
  lifecycle_policy = "{\"rules\":[${join(",", local.lifecycle_rule_json)}]}"
}

# trivy:ignore:AWS-0031 Mutability is var.image_tag_mutability and defaults to IMMUTABLE, which is what prod uses and what the scanner is asking for. Dev passes MUTABLE on purpose so a tag tracks a branch; its images are disposable and nothing is audited or rolled back from them. Suppressed here because the variable makes it unresolvable at the call site.
resource "aws_ecr_repository" "this" {
  name                 = var.name
  image_tag_mutability = var.image_tag_mutability
  force_delete         = var.force_delete

  image_scanning_configuration {
    scan_on_push = var.scan_on_push
  }

  encryption_configuration {
    encryption_type = var.kms_key_arn == null ? "AES256" : "KMS"
    kms_key         = var.kms_key_arn
  }

  tags = {
    Name = var.name
  }
}

resource "aws_ecr_lifecycle_policy" "this" {
  count = length(local.lifecycle_rule_json) > 0 ? 1 : 0

  repository = aws_ecr_repository.this.name
  policy     = local.lifecycle_policy
}

data "aws_iam_policy_document" "pull" {
  count = length(var.pull_account_ids) > 0 ? 1 : 0

  statement {
    sid    = "CrossAccountPull"
    effect = "Allow"

    principals {
      type        = "AWS"
      identifiers = [for a in var.pull_account_ids : "arn:aws:iam::${a}:root"]
    }

    actions = [
      "ecr:BatchGetImage",
      "ecr:GetDownloadUrlForLayer",
      "ecr:BatchCheckLayerAvailability",
      "ecr:DescribeImages",
    ]
  }
}

resource "aws_ecr_repository_policy" "pull" {
  count = length(var.pull_account_ids) > 0 ? 1 : 0

  repository = aws_ecr_repository.this.name
  policy     = data.aws_iam_policy_document.pull[0].json
}
