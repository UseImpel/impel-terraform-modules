# One Fargate service running a fixed set of interdependent containers that
# share EFS-backed volumes: log group, IAM roles, task security group, task
# definition, target group and listener rule, the service.
#
# Deliberately not ecs-service with a flag: that module's defaults — rolling
# 100/200 deploys, AZ rebalancing enabled, autoscaling always on — assume
# stateless replicas. This task holds the sole writer to its own postgres and
# minio volumes, so a second task started before the first stops would fight
# it for those mounts. Every deploy here stops the running task before
# starting its replacement, there is exactly one task, and there is no
# autoscaling to contend with it.

data "aws_region" "current" {}

locals {
  log_group_name = coalesce(var.log_group_name, "/ecs/${var.name}/service")

  all_container_secrets = merge([for c in values(var.containers) : c.secrets]...)

  # Drives count on the target group, listener rule and ALB ingress rule, so it
  # must be resolvable at plan time. var.listener_arn is unknown until the load
  # balancer exists, which makes it unusable here — hence the separate flag.
  attach_lb = var.attach_load_balancer

  # Target group names are capped at 32 characters.
  target_group_name = substr(var.name, 0, 32)

  primary_container_port = var.containers[var.primary_container_name].port

  container_definitions = [
    for name, c in var.containers : merge(
      {
        name      = name
        image     = c.image
        cpu       = c.cpu
        memory    = c.memory
        essential = true

        environment = [
          for k, v in c.environment_variables : { name = k, value = v }
        ]

        secrets = [
          for k, v in c.secrets : { name = k, valueFrom = v }
        ]

        logConfiguration = {
          logDriver = "awslogs"
          options = {
            "awslogs-group"         = local.log_group_name
            "awslogs-region"        = data.aws_region.current.region
            "awslogs-stream-prefix" = name
          }
        }

        readonlyRootFilesystem = c.readonly_root_filesystem
      },
      c.port != null ? {
        portMappings = [{
          containerPort = c.port
          hostPort      = c.port
          protocol      = "tcp"
        }]
      } : {},
      length(c.command) > 0 ? { command = c.command } : {},
      length(c.entrypoint) > 0 ? { entryPoint = c.entrypoint } : {},
      length(c.health_check_command) > 0 ? {
        healthCheck = {
          command     = c.health_check_command
          interval    = c.health_check_interval
          timeout     = c.health_check_timeout
          retries     = c.health_check_retries
          startPeriod = c.health_check_start_period
        }
      } : {},
      c.stop_timeout != null ? { stopTimeout = c.stop_timeout } : {},
      length(c.depends_on) > 0 ? {
        dependsOn = [
          for d in c.depends_on : {
            containerName = d.container_name
            condition     = d.condition
          }
        ]
      } : {},
      length(c.mount_points) > 0 ? {
        mountPoints = [
          for m in c.mount_points : {
            sourceVolume  = m.volume_name
            containerPath = m.container_path
            readOnly      = m.read_only
          }
        ]
      } : {},
    )
  ]
}

resource "aws_cloudwatch_log_group" "this" {
  #checkov:skip=CKV_AWS_158:Application logs are read by on-call through the console; a CMK adds key policy management on every reader for no threat model this estate has.
  #checkov:skip=CKV_AWS_338:Retention is var.log_retention_days.
  name              = local.log_group_name
  retention_in_days = var.log_retention_days

  tags = {
    Name = local.log_group_name
  }
}

# ---------------------------------------------------------------------------
# IAM
#
# The execution role is used by the ECS agent to pull images and read secrets
# before the containers start. The task role is what application code assumes
# at runtime. Merging them would give every container read access to every
# secret the task definition names.
# ---------------------------------------------------------------------------

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

resource "aws_iam_role" "execution" {
  name               = "${var.name}-execution"
  description        = "Pulls images and reads secrets for ${var.name} before its containers start."
  assume_role_policy = data.aws_iam_policy_document.assume.json
}

data "aws_iam_policy_document" "execution" {
  #checkov:skip=CKV_AWS_356:ecr:GetAuthorizationToken and the ECR layer reads are not resource-scopable in the ECR API. Secret access below is scoped to exactly the ARNs named across every container's secrets.
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
    resources = ["*"]
  }

  statement {
    sid    = "Logs"
    effect = "Allow"
    actions = [
      "logs:CreateLogStream",
      "logs:PutLogEvents",
    ]
    resources = ["${aws_cloudwatch_log_group.this.arn}:*"]
  }

  # Scoped to exactly the secrets this task definition names.
  dynamic "statement" {
    for_each = length(local.all_container_secrets) > 0 ? [1] : []

    content {
      sid     = "ReadSecrets"
      effect  = "Allow"
      actions = ["secretsmanager:GetSecretValue"]
      resources = distinct([
        for v in values(local.all_container_secrets) : length(split(":", v)) > 6 ? join(":", slice(split(":", v), 0, 7)) : v
      ])
    }
  }

  dynamic "statement" {
    for_each = length(var.secret_kms_key_arns) > 0 ? [1] : []

    content {
      sid       = "DecryptSecrets"
      effect    = "Allow"
      actions   = ["kms:Decrypt"]
      resources = var.secret_kms_key_arns
    }
  }
}

resource "aws_iam_role_policy" "execution" {
  name   = "task-execution"
  role   = aws_iam_role.execution.id
  policy = data.aws_iam_policy_document.execution.json
}

resource "aws_iam_role" "task" {
  name               = "${var.name}-task"
  description        = "Runtime identity for ${var.name} application code."
  assume_role_policy = data.aws_iam_policy_document.assume.json
}

resource "aws_iam_role_policy" "task" {
  count = var.task_role_policy_json != null ? 1 : 0

  name   = "task"
  role   = aws_iam_role.task.id
  policy = var.task_role_policy_json
}

# count, not for_each keyed on the ARN: a policy created in this same apply
# has an unknown ARN at plan, and for_each rejects unknown keys. Length is
# known even when the ARN is not.
resource "aws_iam_role_policy_attachment" "task" {
  count = length(var.task_role_policy_arns)

  role       = aws_iam_role.task.name
  policy_arn = var.task_role_policy_arns[count.index]
}

# ECS Exec needs the SSM messages channel on the task role, not the execution
# role: the agent runs inside the task.
data "aws_iam_policy_document" "execute_command" {
  count = var.enable_execute_command ? 1 : 0

  statement {
    sid    = "EcsExec"
    effect = "Allow"
    actions = [
      "ssmmessages:CreateControlChannel",
      "ssmmessages:CreateDataChannel",
      "ssmmessages:OpenControlChannel",
      "ssmmessages:OpenDataChannel",
    ]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "execute_command" {
  count = var.enable_execute_command ? 1 : 0

  name   = "ecs-exec"
  role   = aws_iam_role.task.id
  policy = data.aws_iam_policy_document.execute_command[0].json
}

# ---------------------------------------------------------------------------
# Networking
# ---------------------------------------------------------------------------

resource "aws_security_group" "task" {
  name        = "${var.name}-task"
  description = "Only the load balancer may reach ${var.name} tasks, on the primary container's port."
  vpc_id      = var.vpc_id

  tags = {
    Name = "${var.name}-task"
  }
}

resource "aws_vpc_security_group_ingress_rule" "from_lb" {
  count = local.attach_lb ? 1 : 0

  security_group_id = aws_security_group.task.id
  description       = "Primary container port from the load balancer only."

  referenced_security_group_id = var.load_balancer_security_group_id
  from_port                    = local.primary_container_port
  to_port                      = local.primary_container_port
  ip_protocol                  = "tcp"
}

# Tasks reach ECR, Secrets Manager, EFS and third-party APIs (vexa.ai)
# outbound. Ingress is where the control lives.
# trivy:ignore:AWS-0104 Containers call third-party APIs whose address ranges are not enumerable, and reach EFS mount targets across both private subnets. Narrowing this would break outbound integrations and mounting alike.
resource "aws_vpc_security_group_egress_rule" "all" {
  security_group_id = aws_security_group.task.id
  description       = "Outbound to AWS services, EFS mount targets and third-party APIs."

  cidr_ipv4   = "0.0.0.0/0"
  ip_protocol = "-1"
}

# ---------------------------------------------------------------------------
# Task definition
# ---------------------------------------------------------------------------

resource "aws_ecs_task_definition" "this" {
  family                   = var.name
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = tostring(var.cpu)
  memory                   = tostring(var.memory)

  execution_role_arn = aws_iam_role.execution.arn
  task_role_arn      = aws_iam_role.task.arn

  runtime_platform {
    cpu_architecture        = "X86_64"
    operating_system_family = "LINUX"
  }

  ephemeral_storage {
    size_in_gib = var.ephemeral_storage_gib
  }

  dynamic "volume" {
    for_each = var.volumes

    content {
      name = volume.key

      efs_volume_configuration {
        file_system_id     = volume.value.file_system_id
        transit_encryption = volume.value.transit_encryption ? "ENABLED" : "DISABLED"

        authorization_config {
          access_point_id = volume.value.access_point_id
          iam             = volume.value.iam_authorization ? "ENABLED" : "DISABLED"
        }
      }
    }
  }

  container_definitions = jsonencode(local.container_definitions)

  lifecycle {
    precondition {
      condition     = contains(keys(var.containers), var.primary_container_name)
      error_message = "primary_container_name must name one of the containers in var.containers."
    }

    precondition {
      condition     = local.primary_container_port != null
      error_message = "The primary container named by primary_container_name must set a port."
    }

    precondition {
      condition = alltrue(flatten([
        for c in values(var.containers) : [
          for m in c.mount_points : contains(keys(var.volumes), m.volume_name)
        ]
      ]))
      error_message = "Every container mount_points.volume_name must name a key in var.volumes."
    }

    precondition {
      condition     = sum([for c in values(var.containers) : c.cpu]) <= var.cpu
      error_message = "The sum of every container's cpu reservation must not exceed the task-level cpu."
    }

    precondition {
      condition     = sum([for c in values(var.containers) : c.memory]) <= var.memory
      error_message = "The sum of every container's memory reservation must not exceed the task-level memory."
    }
  }

  tags = {
    Name = var.name
  }
}

# ---------------------------------------------------------------------------
# Load balancer attachment
# ---------------------------------------------------------------------------

resource "aws_lb_target_group" "this" {
  #checkov:skip=CKV_AWS_378:TLS terminates at the load balancer; the hop to the task is HTTP inside a private subnet, reaching a security group that accepts the load balancer alone.
  count = local.attach_lb ? 1 : 0

  name        = local.target_group_name
  port        = local.primary_container_port
  protocol    = "HTTP"
  vpc_id      = var.vpc_id
  target_type = "ip" # awsvpc tasks register by ENI address

  deregistration_delay = var.deregistration_delay

  health_check {
    enabled             = true
    path                = var.health_check_path
    protocol            = "HTTP"
    port                = "traffic-port"
    matcher             = var.health_check_matcher
    interval            = var.target_group_health_check.interval
    timeout             = var.target_group_health_check.timeout
    healthy_threshold   = var.target_group_health_check.healthy_threshold
    unhealthy_threshold = var.target_group_health_check.unhealthy_threshold
  }

  tags = {
    Name = var.name
  }

  # A target group cannot be deleted while a listener rule forwards to it, so a
  # change forcing replacement must create the new one first.
  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_lb_listener_rule" "this" {
  count = local.attach_lb ? 1 : 0

  listener_arn = var.listener_arn
  priority     = var.listener_rule_priority

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.this[0].arn
  }

  dynamic "condition" {
    for_each = length(var.listener_rule_host_headers) > 0 ? [1] : []

    content {
      host_header {
        values = var.listener_rule_host_headers
      }
    }
  }

  dynamic "condition" {
    for_each = length(var.listener_rule_path_patterns) > 0 ? [1] : []

    content {
      path_pattern {
        values = var.listener_rule_path_patterns
      }
    }
  }

  lifecycle {
    precondition {
      condition     = length(var.listener_rule_host_headers) > 0 || length(var.listener_rule_path_patterns) > 0
      error_message = "A listener rule needs at least one host header or path pattern; a rule with no condition never matches."
    }

    precondition {
      condition     = var.listener_rule_priority != null
      error_message = "listener_rule_priority is required when attach_load_balancer is true: priorities must be unique per listener and cannot be inferred."
    }

    precondition {
      condition     = var.load_balancer_security_group_id != null
      error_message = "load_balancer_security_group_id is required when attach_load_balancer is true, or the tasks accept no ingress and every target fails its health check."
    }

    precondition {
      condition     = var.listener_arn != null
      error_message = "listener_arn is required when attach_load_balancer is true."
    }
  }
}

# ---------------------------------------------------------------------------
# Service
#
# Two variants of the same service, selected by var.continuous_deployment —
# the same mechanism as ecs-service. `ignore_changes` takes a static list, so
# the choice has to be made with count rather than inside one resource. Keep
# the argument bodies identical; only the lifecycle block differs.
#
# desired_count is the literal 1, not a variable: KTD2 pins this task to
# exactly one runner, with no autoscaling target to contend with a manual
# change, so there is nothing to ignore_changes here the way ecs-service must
# for its autoscaled desired_count.
# ---------------------------------------------------------------------------

resource "aws_ecs_service" "this" {
  count           = var.continuous_deployment ? 0 : 1
  name            = var.name
  cluster         = var.cluster_arn
  task_definition = aws_ecs_task_definition.this.arn
  desired_count   = 1

  capacity_provider_strategy {
    capacity_provider = var.capacity_provider
    weight            = 1
    base              = 0
  }

  platform_version = var.platform_version

  deployment_controller {
    type = "ECS"
  }

  # A deployment that never reaches steady state rolls itself back.
  deployment_circuit_breaker {
    enable   = true
    rollback = true
  }

  # Stop-then-start, not rolling: the task holds the sole writer to its own
  # EFS-backed postgres and minio volumes, so a second task cannot exist
  # alongside the first even briefly. AWS additionally rejects
  # availability_zone_rebalancing = "ENABLED" whenever maximum_percent <= 100.
  deployment_minimum_healthy_percent = 0
  deployment_maximum_percent         = 100
  availability_zone_rebalancing      = "DISABLED"

  health_check_grace_period_seconds = local.attach_lb ? var.health_check_grace_period : null
  enable_execute_command            = var.enable_execute_command

  enable_ecs_managed_tags = true
  propagate_tags          = "SERVICE"

  network_configuration {
    subnets          = var.subnet_ids
    security_groups  = [aws_security_group.task.id]
    assign_public_ip = false
  }

  dynamic "load_balancer" {
    for_each = local.attach_lb ? [1] : []

    content {
      target_group_arn = aws_lb_target_group.this[0].arn
      container_name   = var.primary_container_name
      container_port   = local.primary_container_port
    }
  }

  tags = {
    Name = var.name
  }

  # The listener rule must exist before the service registers targets.
  depends_on = [aws_lb_listener_rule.this]
}

# Same service, but the application repository rolls new images onto it. See
# var.continuous_deployment.
resource "aws_ecs_service" "continuous" {
  count           = var.continuous_deployment ? 1 : 0
  name            = var.name
  cluster         = var.cluster_arn
  task_definition = aws_ecs_task_definition.this.arn
  desired_count   = 1

  capacity_provider_strategy {
    capacity_provider = var.capacity_provider
    weight            = 1
    base              = 0
  }

  platform_version = var.platform_version

  deployment_controller {
    type = "ECS"
  }

  deployment_circuit_breaker {
    enable   = true
    rollback = true
  }

  deployment_minimum_healthy_percent = 0
  deployment_maximum_percent         = 100
  availability_zone_rebalancing      = "DISABLED"

  health_check_grace_period_seconds = local.attach_lb ? var.health_check_grace_period : null
  enable_execute_command            = var.enable_execute_command

  enable_ecs_managed_tags = true
  propagate_tags          = "SERVICE"

  network_configuration {
    subnets          = var.subnet_ids
    security_groups  = [aws_security_group.task.id]
    assign_public_ip = false
  }

  dynamic "load_balancer" {
    for_each = local.attach_lb ? [1] : []

    content {
      target_group_arn = aws_lb_target_group.this[0].arn
      container_name   = var.primary_container_name
      container_port   = local.primary_container_port
    }
  }

  tags = {
    Name = var.name
  }

  lifecycle {
    # The application's own deploy pipeline advances the running task
    # definition with `aws ecs update-service`. Without this, the next apply
    # would roll the service back to the digest last rendered here — silently
    # reverting a deploy that already shipped.
    ignore_changes = [task_definition]
  }

  # The listener rule must exist before the service registers targets.
  depends_on = [aws_lb_listener_rule.this]
}

locals {
  # One of the two counts is always zero, so exactly one element exists.
  service = one(concat(aws_ecs_service.this, aws_ecs_service.continuous))
}
