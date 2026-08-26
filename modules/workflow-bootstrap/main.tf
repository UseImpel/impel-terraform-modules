# One-shot Fargate task that runs Workflow schema bootstrap (`setupDatabase`)
# against a service's Aurora. Not a service: nothing stays running. The
# application repository pushes the bootstrap tag and calls `ecs run-task`.
#
# Roles, security group and log group come from the long-running service so
# this task can reach Aurora and write logs without a second identity.

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

locals {
  container_definition = {
    name      = "workflow-bootstrap"
    image     = var.container_image
    essential = true

    environment = [
      for k, v in var.environment_variables : { name = k, value = v }
    ]

    secrets = [
      for k, v in var.container_secrets : { name = k, valueFrom = v }
    ]

    logConfiguration = {
      logDriver = "awslogs"
      options = {
        "awslogs-group"         = var.log_group_name
        "awslogs-region"        = data.aws_region.current.region
        "awslogs-stream-prefix" = "workflow-bootstrap"
      }
    }

    readonlyRootFilesystem = true
    stopTimeout            = 120
  }

  task_definition_arn_prefix = "arn:aws:ecs:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:task-definition/${var.family}"
}

resource "aws_ecs_task_definition" "this" {
  family                   = var.family
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = tostring(var.cpu)
  memory                   = tostring(var.memory)

  execution_role_arn = var.execution_role_arn
  task_role_arn      = var.task_role_arn

  runtime_platform {
    cpu_architecture        = "X86_64"
    operating_system_family = "LINUX"
  }

  container_definitions = jsonencode([local.container_definition])

  tags = {
    Name = var.family
  }
}

data "aws_iam_policy_document" "runtask" {
  statement {
    sid    = "RunBootstrapTask"
    effect = "Allow"
    actions = [
      "ecs:RunTask",
    ]
    resources = [
      local.task_definition_arn_prefix,
      "${local.task_definition_arn_prefix}:*",
    ]

    condition {
      test     = "ArnEquals"
      variable = "ecs:cluster"
      values   = [var.cluster_arn]
    }
  }
}

resource "aws_iam_role_policy" "runtask" {
  name   = "run-workflow-bootstrap"
  role   = var.deploy_role_name
  policy = data.aws_iam_policy_document.runtask.json
}
