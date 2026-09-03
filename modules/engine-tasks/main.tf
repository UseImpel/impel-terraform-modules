# One-off Fargate task definitions for the code-intelligence engine fleet.
# Nothing here is a service: the worker and query services launch these
# families ad hoc via ecs:RunTask and they terminate when the job ends.
#
# Terraform port of the engine fleet in code-intelligence
# infra/aws/lib/runtime-stack.ts: the engineTask() helper (task definitions),
# the engine/checkout security groups, and the RunTask grants the CDK attaches
# to the query and worker task roles (published here as standalone policies
# because those roles belong to ecs-service module instances).

data "aws_region" "current" {}

locals {
  # Mirrors runtime-stack.ts engineTask(): family
  # impel-code-intelligence-sea-engine-<name>.
  families = { for k in keys(var.tasks) : k => "${var.name_prefix}-engine-${k}" }

  # arn:aws:ecs:<region>:<account>:task/<cluster-name>/* — the resource shape
  # the CDK builds with formatArn for DescribeTasks/StopTask/TagResource
  # (runtime-stack.ts:324-329). Derived from the cluster ARN so region and
  # account pins are inherited rather than restated.
  engine_task_wildcard_arn = "${replace(var.cluster_arn, ":cluster/", ":task/")}/*"

  # runtime-stack.ts:317-323: query may run every engine family EXCEPT
  # checkout; worker may run them all, checkout included.
  runtask_grants = {
    worker = {
      families        = keys(var.tasks)
      execution_kinds = ["checkout", "index"] # runtime-stack.ts:332
    }
    query = {
      families        = [for k in keys(var.tasks) : k if k != "checkout"]
      execution_kinds = ["query"] # runtime-stack.ts:331
    }
  }
}

# Logs — one shared group; each engine keeps its own stream prefix

resource "aws_cloudwatch_log_group" "engine" {
  #checkov:skip=CKV_AWS_158:Engine logs are read by on-call through the console; a CMK adds key policy management on every reader for no threat model this estate has.
  #checkov:skip=CKV_AWS_338:Retention is var.log_retention_days: 7 in dev. A year of one-off engine task logs is cost with no reader.
  name              = "/ecs/${var.name_prefix}/engine"
  retention_in_days = var.log_retention_days

  tags = {
    Name = "/ecs/${var.name_prefix}/engine"
  }
}

# IAM roles
#
# One execution role and one task role shared by the whole fleet, exactly as
# the CDK does (runtime-stack.ts:184-197). The task role carries NO policies:
# sealed engine tasks are credential-free by design — all artifact I/O uses
# short-lived prefix-scoped presigned URLs minted by the services, so there
# is nothing to attach. Do not add S3 or KMS here.

data "aws_iam_policy_document" "assume" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "task" {
  name               = "${var.name_prefix}-engine"
  description        = "Credential-free engine runtime; all I/O uses short-lived prefix-scoped presigned URLs."
  assume_role_policy = data.aws_iam_policy_document.assume.json
}

resource "aws_iam_role" "execution" {
  name               = "${var.name_prefix}-engine-execution"
  description        = "Pulls engine images and writes logs before an engine container starts."
  assume_role_policy = data.aws_iam_policy_document.assume.json
}

data "aws_iam_policy_document" "execution" {
  #checkov:skip=CKV_AWS_356:ecr:GetAuthorizationToken is not resource-scopable in the ECR API. ECR layer reads and log writes are scoped below.
  # GetAuthorizationToken has no resource scope in the ECR API. Layer and
  # manifest reads below stay limited to the caller-supplied engine repositories.
  statement {
    sid       = "EcrAuth"
    effect    = "Allow"
    actions   = ["ecr:GetAuthorizationToken"]
    resources = ["*"]
  }

  statement {
    sid    = "EcrPull"
    effect = "Allow"
    actions = [
      "ecr:BatchCheckLayerAvailability",
      "ecr:GetDownloadUrlForLayer",
      "ecr:BatchGetImage",
    ]
    resources = var.ecr_repository_arns
  }

  statement {
    sid    = "Logs"
    effect = "Allow"
    actions = [
      "logs:CreateLogStream",
      "logs:PutLogEvents",
    ]
    resources = ["${aws_cloudwatch_log_group.engine.arn}:*"]
  }
}

resource "aws_iam_role_policy" "execution" {
  name   = "task-execution"
  role   = aws_iam_role.execution.id
  policy = data.aws_iam_policy_document.execution.json
}

# Task definitions — one per engine, launched only via RunTask

resource "aws_ecs_task_definition" "this" {
  for_each = var.tasks

  family                   = local.families[each.key]
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = tostring(each.value.cpu)
  memory                   = tostring(each.value.memory)

  execution_role_arn = aws_iam_role.execution.arn
  task_role_arn      = aws_iam_role.task.arn

  runtime_platform {
    cpu_architecture        = "X86_64"
    operating_system_family = "LINUX"
  }

  ephemeral_storage {
    size_in_gib = each.value.ephemeral_gib
  }

  container_definitions = jsonencode([
    {
      name      = var.engine_container_name
      image     = each.value.image
      essential = true

      entryPoint = each.value.entrypoint

      # Engines unpack repository checkouts and write indexes onto the
      # ephemeral volume; a read-only root breaks them.
      readonlyRootFilesystem = false
      stopTimeout            = 120

      ulimits = [
        {
          name      = "nofile"
          softLimit = 65536
          hardLimit = 65536
        }
      ]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.engine.name
          "awslogs-region"        = data.aws_region.current.region
          "awslogs-stream-prefix" = each.key
        }
      }
    }
  ])

  tags = {
    Name = local.families[each.key]
  }
}

# Security groups
#
# Two network postures (runtime-stack.ts:125-155). Checkout tasks reach
# repository hosts on the internet; sealed engine tasks reach only the VPC
# resolver, the interface endpoints and the S3 gateway endpoint. Neither has
# ingress. The provider revokes the SG default allow-all egress, so each
# group's egress is exactly what is declared below.

resource "aws_security_group" "checkout" {
  #checkov:skip=CKV2_AWS_5:Checkout tasks attach this group dynamically through ECS RunTask awsvpcConfiguration; the task ENI does not exist in this reusable module.
  name        = "${var.name_prefix}-checkout"
  description = "Checkout-only tasks may reach repository hosts and terminate before indexing begins."
  vpc_id      = var.vpc_id

  tags = {
    Name = "${var.name_prefix}-checkout"
  }
}

# trivy:ignore:AWS-0104 CDK parity (runtime-stack.ts:125-130 allowAllOutbound:true): checkout clones from customer repository hosts whose addresses are not enumerable; the sealed engine group below is where egress is narrowed.
resource "aws_vpc_security_group_egress_rule" "checkout_all" {
  #checkov:skip=CKV_AWS_382:CDK parity (runtime-stack.ts:125-130 allowAllOutbound:true): checkout clones from arbitrary customer repository hosts; the sealed engine group is the narrowed one.
  security_group_id = aws_security_group.checkout.id
  description       = "Outbound to repository hosts, DNS and AWS endpoints."

  cidr_ipv4   = "0.0.0.0/0"
  ip_protocol = "-1"
}

resource "aws_security_group" "engine" {
  #checkov:skip=CKV2_AWS_5:Engine tasks attach this group dynamically through ECS RunTask awsvpcConfiguration; the task ENI does not exist in this reusable module.
  name        = "${var.name_prefix}-engine"
  description = "Index and query engine tasks have no inbound or public internet access."
  vpc_id      = var.vpc_id

  tags = {
    Name = "${var.name_prefix}-engine"
  }
}

# runtime-stack.ts:136-140
resource "aws_vpc_security_group_egress_rule" "engine_dns_udp" {
  security_group_id = aws_security_group.engine.id
  description       = "VPC DNS over UDP"

  cidr_ipv4   = var.vpc_dns_cidr
  from_port   = 53
  to_port     = 53
  ip_protocol = "udp"
}

# runtime-stack.ts:141-145
resource "aws_vpc_security_group_egress_rule" "engine_dns_tcp" {
  security_group_id = aws_security_group.engine.id
  description       = "VPC DNS over TCP"

  cidr_ipv4   = var.vpc_dns_cidr
  from_port   = 53
  to_port     = 53
  ip_protocol = "tcp"
}

# runtime-stack.ts:146-150
resource "aws_vpc_security_group_egress_rule" "engine_endpoints" {
  security_group_id = aws_security_group.engine.id
  description       = "Private ECR and CloudWatch Logs interface endpoints"

  referenced_security_group_id = var.endpoint_security_group_id
  from_port                    = 443
  to_port                      = 443
  ip_protocol                  = "tcp"
}

# runtime-stack.ts:151-155
resource "aws_vpc_security_group_egress_rule" "engine_s3" {
  security_group_id = aws_security_group.engine.id
  description       = "Regional S3 gateway endpoint for presigned artifact transfers"

  prefix_list_id = var.s3_prefix_list_id
  from_port      = 443
  to_port        = 443
  ip_protocol    = "tcp"
}

# RunTask policies for the service task roles
#
# The CDK adds these statements straight onto the query and worker task roles
# (runtime-stack.ts:330-373). Here those roles are created by ecs-service
# module instances, so the grants are standalone policies the caller attaches
# via that module's task_role_policy_arns.

data "aws_iam_policy_document" "runtask" {
  for_each = local.runtask_grants

  statement {
    sid     = "RunEngineTask"
    effect  = "Allow"
    actions = ["ecs:RunTask"]

    # Revision-agnostic per-family ARNs; the CDK grants the revision-pinned
    # ARNs it just registered (runtime-stack.ts:336), which Terraform cannot
    # do stably across revisions.
    resources = [
      for k in each.value.families : "${aws_ecs_task_definition.this[k].arn_without_revision}:*"
    ]

    # runtime-stack.ts:338 — only onto this cluster.
    condition {
      test     = "ArnEquals"
      variable = "ecs:cluster"
      values   = [var.cluster_arn]
    }

    # runtime-stack.ts:340 — every launch is tagged to the application.
    condition {
      test     = "StringEquals"
      variable = "aws:RequestTag/Application"
      values   = [var.application_tag]
    }

    # runtime-stack.ts:341 with 331-332 — worker launches checkout/index,
    # query launches query, never each other's kinds.
    condition {
      test     = "StringEquals"
      variable = "aws:RequestTag/ExecutionKind"
      values   = each.value.execution_kinds
    }

    # runtime-stack.ts:343-345 — no tag keys beyond the contract, so a task
    # cannot be mislabeled into another service's Describe/Stop scope.
    condition {
      test     = "ForAllValues:StringEquals"
      variable = "aws:TagKeys"
      values   = ["Application", "Tenant", "Engine", "ExecutionKind"]
    }
  }

  statement {
    sid     = "ManageOwnEngineTasks"
    effect  = "Allow"
    actions = ["ecs:DescribeTasks", "ecs:StopTask"]

    # runtime-stack.ts:324-329,350 — tasks on this cluster only; the ARN
    # carries the region pin the CDK expresses as aws:RequestedRegion (353).
    resources = [local.engine_task_wildcard_arn]

    # Tighter than the CDK's aws:RequestedRegion (runtime-stack.ts:353):
    # pins region, account and cluster in one key.
    condition {
      test     = "ArnEquals"
      variable = "ecs:cluster"
      values   = [var.cluster_arn]
    }

    # runtime-stack.ts:354 — only this application's tasks.
    condition {
      test     = "StringEquals"
      variable = "aws:ResourceTag/Application"
      values   = [var.application_tag]
    }

    # runtime-stack.ts:355 — only tasks of the kinds this role launches.
    condition {
      test     = "StringEquals"
      variable = "aws:ResourceTag/ExecutionKind"
      values   = each.value.execution_kinds
    }
  }

  statement {
    sid     = "TagAtLaunch"
    effect  = "Allow"
    actions = ["ecs:TagResource"]

    # runtime-stack.ts:361 — same task wildcard; region pinned by the ARN
    # rather than the CDK's aws:RequestedRegion (364).
    resources = [local.engine_task_wildcard_arn]

    # runtime-stack.ts:365 — tagging only as a side effect of RunTask, never
    # retagging a live task into a different Describe/Stop scope.
    condition {
      test     = "StringEquals"
      variable = "ecs:CreateAction"
      values   = ["RunTask"]
    }

    # Same tag contract as RunEngineTask (runtime-stack.ts:340-345); the tags
    # applied at launch cannot differ from the ones RunTask allowed.
    condition {
      test     = "StringEquals"
      variable = "aws:RequestTag/Application"
      values   = [var.application_tag]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:RequestTag/ExecutionKind"
      values   = each.value.execution_kinds
    }

    condition {
      test     = "ForAllValues:StringEquals"
      variable = "aws:TagKeys"
      values   = ["Application", "Tenant", "Engine", "ExecutionKind"]
    }
  }

  statement {
    sid     = "PassEngineRoles"
    effect  = "Allow"
    actions = ["iam:PassRole"]

    # runtime-stack.ts:369-372 — exactly the two fleet roles, and (tighter
    # than the CDK) only into ECS task launches.
    resources = [
      aws_iam_role.task.arn,
      aws_iam_role.execution.arn,
    ]

    condition {
      test     = "StringEquals"
      variable = "iam:PassedToService"
      values   = ["ecs-tasks.amazonaws.com"]
    }
  }
}

resource "aws_iam_policy" "runtask" {
  for_each = local.runtask_grants

  name        = "${var.name_prefix}-engine-runtask-${each.key}"
  description = "Lets the ${each.key} service run and manage ${join("/", each.value.execution_kinds)} engine tasks on ${var.name_prefix}."
  policy      = data.aws_iam_policy_document.runtask[each.key].json

  tags = {
    Name = "${var.name_prefix}-engine-runtask-${each.key}"
  }
}
