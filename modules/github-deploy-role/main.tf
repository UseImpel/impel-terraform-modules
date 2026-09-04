# The identity an application repository assumes to ship a service: push an
# image to that service's repository, then roll it onto the running service.
#
# Two properties make this safe to hand to a repository this one does not own.
#
# The trust policy names exactly one OIDC subject, so only the branch below can
# assume the role. GitHub mints a token with that subject and no other, which
# means "merge to <branch> deploys" is enforced by AWS rather than by the
# workflow file -- editing the YAML cannot widen it.
#
# Permissions name a caller-given list of ECR repositories and ECS services,
# so a compromised repository stops at its own services -- whether a service
# builds from several repositories (meets) or one repository deploys several
# (code intelligence).
#
# ecr:GetAuthorizationToken and ecs:RegisterTaskDefinition cannot be
# resource-scoped; the API rejects a resource on either. Both annotated below.

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

locals {
  oidc_host = "token.actions.githubusercontent.com"

  # GitHub encodes the minting ref into the subject. This is the whole security
  # boundary, so it is built here rather than taken as a string. Repositories
  # created after 2026-07-15 use an immutable owner/repository-ID prefix; the
  # name-based form stays the default for existing callers.
  repository_owner = split("/", var.github_repository)[0]
  repository_name  = split("/", var.github_repository)[1]
  subject_prefix = var.github_oidc_ids == null ? "repo:${var.github_repository}" : format(
    "repo:%s@%d/%s@%d",
    local.repository_owner,
    var.github_oidc_ids.owner_id,
    local.repository_name,
    var.github_oidc_ids.repository_id,
  )
  subject = "${local.subject_prefix}:ref:refs/heads/${var.deploy_branch}"

  service_arns = [
    for service_name in var.service_names :
    "arn:aws:ecs:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:service/${var.cluster_name}/${service_name}"
  ]
}

data "aws_iam_policy_document" "trust" {
  #checkov:skip=CKV_AWS_358:False positive on a parameterised module. The check splits the sub value on ":" and requires field 1 to look like owner/repo; here it is still ${var.github_repository} at scan time, so it cannot match. The rendered policy is exactly what the check asks for -- StringEquals on one fully-qualified subject, no wildcard, no abusable claim -- and an identical literal policy passes. Verified by rendering both.
  statement {
    sid     = "GitHubOidc"
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = ["arn:aws:iam::${data.aws_caller_identity.current.account_id}:oidc-provider/${local.oidc_host}"]
    }

    # StringEquals, not StringLike. A wildcard here would let any branch in the
    # repository -- including one opened by a fork's pull request -- deploy.
    #
    # The condition keys are written out rather than interpolated from
    # local.oidc_host: policy analysers match on this literal to recognise a
    # GitHub trust policy at all, and an interpolation reads to them as an
    # unrestricted federated principal.
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:sub"
      values   = [local.subject]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

data "aws_iam_policy_document" "deploy" {
  #checkov:skip=CKV_AWS_356:Three statements use "*" because AWS rejects a resource on those actions: ecr:GetAuthorizationToken, ecs:RegisterTaskDefinition (a family has no ARN before its first revision), and the read-only Describe/List calls, whose revision ARNs carry no per-service prefix. Every action that can be scoped is -- the named ECR repositories, the named ECS services, two pass-roles behind a PassedToService condition. See the Scope table in README.md.
  # Exchanges credentials for a docker login. The API rejects any resource
  # other than "*", and the token it returns is still bounded by the
  # repository-scoped grants below.
  statement {
    sid       = "EcrLogin"
    effect    = "Allow"
    actions   = ["ecr:GetAuthorizationToken"]
    resources = ["*"]
  }

  statement {
    sid    = "PushToOwnRepositories"
    effect = "Allow"

    actions = [
      "ecr:BatchCheckLayerAvailability",
      "ecr:InitiateLayerUpload",
      "ecr:UploadLayerPart",
      "ecr:CompleteLayerUpload",
      "ecr:PutImage",
      "ecr:BatchGetImage",
      "ecr:GetDownloadUrlForLayer",
      "ecr:DescribeImages",
    ]

    resources = var.ecr_repository_arns
  }

  # RegisterTaskDefinition takes no resource -- a task definition family does
  # not exist until the first revision is registered, so there is nothing to
  # name. Deploying still requires UpdateService below, which is scoped, and
  # PassRole, which is scoped to this service's two roles: a registered
  # definition that cannot be passed a role cannot run.
  statement {
    sid       = "RegisterTaskDefinition"
    effect    = "Allow"
    actions   = ["ecs:RegisterTaskDefinition"]
    resources = ["*"]
  }

  statement {
    sid    = "DeployOwnService"
    effect = "Allow"

    actions = [
      "ecs:UpdateService",
      "ecs:DescribeServices",
    ]

    resources = local.service_arns
  }

  # Reading a task definition to build the next revision from it. Revisions are
  # account-wide ARNs with no per-service prefix to scope against, and the call
  # is read-only.
  statement {
    sid    = "ReadTaskDefinitions"
    effect = "Allow"

    actions = [
      "ecs:DescribeTaskDefinition",
      "ecs:ListTaskDefinitions",
    ]

    resources = ["*"]
  }

  # Without this the deploy fails on the first RunTask: ECS assumes these roles
  # to start the container. Scoped to this service's own two, so the role
  # cannot pass a more privileged one.
  statement {
    sid       = "PassServiceRoles"
    effect    = "Allow"
    actions   = ["iam:PassRole"]
    resources = var.pass_role_arns

    condition {
      test     = "StringEquals"
      variable = "iam:PassedToService"
      values   = ["ecs-tasks.amazonaws.com"]
    }
  }

  # Only for a Dockerfile that needs a value baked into the image -- next's
  # build inlines its NEXT_PUBLIC_* configuration at compile time, so the value
  # must exist before there is a task to read it. Empty for every other service,
  # which builds from source alone.
  #
  # Scoped to the exact secrets named, never a prefix: this is the one grant on
  # the role that reads data rather than moving an image, and a build that can
  # read a secret can also print it.
  dynamic "statement" {
    for_each = length(var.build_secret_arns) > 0 ? [1] : []

    content {
      sid       = "ReadBuildSecrets"
      effect    = "Allow"
      actions   = ["secretsmanager:GetSecretValue"]
      resources = var.build_secret_arns
    }
  }

  # Waiting for a deployment to reach steady state, and reading logs when it
  # does not. Neither is scopable to one service.
  statement {
    sid    = "ObserveDeployment"
    effect = "Allow"

    actions = [
      "ecs:ListTasks",
      "ecs:DescribeTasks",
      "logs:GetLogEvents",
      "logs:DescribeLogStreams",
    ]

    resources = ["*"]
  }
}

resource "aws_iam_role" "this" {
  name        = var.name
  description = "Deploys ${join(", ", var.service_names)} from ${var.github_repository} on ${var.deploy_branch}. Assumable by that branch alone."

  assume_role_policy = data.aws_iam_policy_document.trust.json

  # A deploy is short. An hour bounds a leaked token without being long enough
  # to interrupt a slow image build.
  max_session_duration = 3600

  tags = {
    Name = var.name
  }
}

resource "aws_iam_role_policy" "deploy" {
  name   = "deploy"
  role   = aws_iam_role.this.id
  policy = data.aws_iam_policy_document.deploy.json
}
