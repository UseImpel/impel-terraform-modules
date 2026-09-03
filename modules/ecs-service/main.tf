# One Fargate service, end to end: log group, IAM roles, task security group,
# task definition, target group and listener rule, the service, and
# target-tracking autoscaling.

data "aws_region" "current" {}

locals {
  log_group_name = coalesce(var.log_group_name, "/ecs/${var.name}/service")
  all_container_secrets = merge(concat(
    [var.container_secrets],
    [for sidecar in values(var.sidecars) : sidecar.container_secrets],
  )...)

  # Drives count on the target group, listener rule and ALB ingress rule, so it
  # must be resolvable at plan time. var.listener_arn is unknown until the load
  # balancer exists, which makes it unusable here — hence the separate flag.
  attach_lb = var.attach_load_balancer

  # Target group names are capped at 32 characters.
  target_group_name = substr(var.name, 0, 32)

  container_definition = merge(
    {
      name      = var.container_name
      image     = var.container_image
      essential = true

      portMappings = [{
        containerPort = var.container_port
        hostPort      = var.container_port
        protocol      = "tcp"
      }]

      environment = [
        for k, v in var.environment_variables : { name = k, value = v }
      ]

      secrets = [
        for k, v in var.container_secrets : { name = k, valueFrom = v }
      ]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = local.log_group_name
          "awslogs-region"        = data.aws_region.current.region
          "awslogs-stream-prefix" = var.container_name
        }
      }

      readonlyRootFilesystem = false
    },
    length(var.command) > 0 ? { command = var.command } : {},
    length(var.entrypoint) > 0 ? { entryPoint = var.entrypoint } : {},
    length(var.health_check_command) > 0 ? {
      healthCheck = {
        command     = var.health_check_command
        interval    = var.health_check_interval
        timeout     = var.health_check_timeout
        retries     = var.health_check_retries
        startPeriod = var.health_check_start_period
      }
    } : {},
    var.container_stop_timeout != null ? { stopTimeout = var.container_stop_timeout } : {},
    length(var.container_dependencies) > 0 ? {
      dependsOn = [
        for dependency in var.container_dependencies : {
          containerName = dependency.container_name
          condition     = dependency.condition
        }
      ]
    } : {},
  )

  sidecar_definitions = [
    for sidecar in values(var.sidecars) : merge(
      {
        name      = sidecar.container_name
        image     = sidecar.container_image
        essential = true

        environment = [
          for k, v in sidecar.environment_variables : { name = k, value = v }
        ]

        secrets = [
          for k, v in sidecar.container_secrets : { name = k, valueFrom = v }
        ]

        logConfiguration = {
          logDriver = "awslogs"
          options = {
            "awslogs-group"         = local.log_group_name
            "awslogs-region"        = data.aws_region.current.region
            "awslogs-stream-prefix" = sidecar.container_name
          }
        }

        readonlyRootFilesystem = sidecar.readonly_root_filesystem
      },
      sidecar.container_port != null ? {
        portMappings = [{
          containerPort = sidecar.container_port
          hostPort      = sidecar.container_port
          protocol      = "tcp"
        }]
      } : {},
      length(sidecar.command) > 0 ? { command = sidecar.command } : {},
      length(sidecar.health_check_command) > 0 ? {
        healthCheck = {
          command     = sidecar.health_check_command
          interval    = sidecar.health_check_interval
          timeout     = sidecar.health_check_timeout
          retries     = sidecar.health_check_retries
          startPeriod = sidecar.health_check_start_period
        }
      } : {},
      sidecar.stop_timeout != null ? { stopTimeout = sidecar.stop_timeout } : {},
    )
  ]

  container_definitions = concat([local.container_definition], local.sidecar_definitions)
}

resource "aws_cloudwatch_log_group" "this" {
  #checkov:skip=CKV_AWS_158:Application logs are read by on-call through the console; a CMK adds key policy management on every reader for no threat model this estate has.
  #checkov:skip=CKV_AWS_338:Retention is var.log_retention_days: 90 days in prod, 7 in dev. A year of dev container logs is cost with no reader.
  name              = local.log_group_name
  retention_in_days = var.log_retention_days

  tags = {
    Name = local.log_group_name
  }
}

# IAM
#
# The execution role is used by the ECS agent to pull the image and read
# secrets before the container starts. The task role is what application code
# assumes at runtime. Merging them would give the application read access to
# every secret the task definition names.

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
  description        = "Pulls images and reads secrets for ${var.name} before the container starts."
  assume_role_policy = data.aws_iam_policy_document.assume.json
}

data "aws_iam_policy_document" "execution" {
  #checkov:skip=CKV_AWS_356:ecr:GetAuthorizationToken and the ECR layer reads are not resource-scopable in the ECR API. Secret access below is scoped to exactly the ARNs in container_secrets.
  # GetAuthorizationToken has no resource scope in the ECR API.
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

# Networking

resource "aws_security_group" "task" {
  name        = "${var.name}-task"
  description = "Only the load balancer may reach ${var.name} tasks."
  vpc_id      = var.vpc_id

  tags = {
    Name = "${var.name}-task"
  }
}

resource "aws_vpc_security_group_ingress_rule" "from_lb" {
  count = local.attach_lb ? 1 : 0

  security_group_id = aws_security_group.task.id
  description       = "Container port from the load balancer only."

  referenced_security_group_id = var.load_balancer_security_group_id
  from_port                    = var.container_port
  to_port                      = var.container_port
  ip_protocol                  = "tcp"
}

# Peer services granted access to this one — the way an api service reaches a
# no-load-balancer service whose security group otherwise accepts nothing.
# Written onto this service's own group, referencing the caller's, so the
# callee declares who may reach it.
resource "aws_vpc_security_group_ingress_rule" "from_peer" {
  for_each = var.ingress_security_group_rules

  security_group_id = aws_security_group.task.id
  description       = "${each.key} to ${var.name} tasks."

  referenced_security_group_id = each.value.security_group_id
  from_port                    = each.value.port
  to_port                      = each.value.port
  ip_protocol                  = "tcp"
}

# Tasks reach ECR, Secrets Manager, data stores and third-party APIs outbound.
# Ingress is where the control lives.
# trivy:ignore:AWS-0104 Tasks call third-party APIs whose address ranges are not enumerable. Narrowing this to the VPC would break every outbound integration; prod leaves egress open on all four services.
resource "aws_vpc_security_group_egress_rule" "all" {
  security_group_id = aws_security_group.task.id
  description       = "Outbound to AWS services, data stores and third-party APIs."

  cidr_ipv4   = "0.0.0.0/0"
  ip_protocol = "-1"
}

# Grants this service access by writing a rule onto each store's security
# group. The direction is deliberate: if the store took a list of client
# security groups instead, any service reading the store's KMS key or endpoint
# would close a dependency cycle Terraform refuses to plan.
resource "aws_vpc_security_group_ingress_rule" "to_data_store" {
  for_each = var.data_store_ingress

  security_group_id = each.value.security_group_id
  description       = "${var.name} tasks to ${each.key}."

  referenced_security_group_id = aws_security_group.task.id
  from_port                    = each.value.port
  to_port                      = each.value.port
  ip_protocol                  = "tcp"
}

# Task definition

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

  dynamic "ephemeral_storage" {
    for_each = var.ephemeral_storage_gib > 0 ? [1] : []

    content {
      size_in_gib = var.ephemeral_storage_gib
    }
  }

  container_definitions = jsonencode(local.container_definitions)

  lifecycle {
    precondition {
      condition     = length(distinct(concat([var.container_name], [for sidecar in values(var.sidecars) : sidecar.container_name]))) == length(var.sidecars) + 1
      error_message = "The primary container and sidecars must have unique container names."
    }

    precondition {
      condition     = alltrue([for dependency in var.container_dependencies : dependency.container_name != var.container_name && contains([for sidecar in values(var.sidecars) : sidecar.container_name], dependency.container_name)])
      error_message = "Every primary-container dependency must name one of the configured sidecars."
    }
  }

  tags = {
    Name = var.name
  }
}

# Load balancer attachment

resource "aws_lb_target_group" "this" {
  #checkov:skip=CKV_AWS_378:TLS terminates at the load balancer; the hop to the task is HTTP inside a private subnet, reaching a security group that accepts the load balancer alone. This matches prod.
  count = local.attach_lb ? 1 : 0

  name        = local.target_group_name
  port        = var.container_port
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

# Service

# Two variants of the same service, selected by var.continuous_deployment.
# `ignore_changes` takes a static list — it cannot be built from a variable — so
# the choice has to be made with count rather than inside one resource. Keep the
# argument bodies identical; only the lifecycle block differs.

resource "aws_ecs_service" "this" {
  count           = var.continuous_deployment ? 0 : 1
  name            = var.name
  cluster         = var.cluster_arn
  task_definition = aws_ecs_task_definition.this.arn
  desired_count   = var.desired_count

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

  deployment_minimum_healthy_percent = 100
  deployment_maximum_percent         = 200

  health_check_grace_period_seconds = local.attach_lb ? var.health_check_grace_period : null
  enable_execute_command            = var.enable_execute_command

  enable_ecs_managed_tags = true
  propagate_tags          = "SERVICE"

  availability_zone_rebalancing = "ENABLED"

  network_configuration {
    subnets          = var.subnet_ids
    security_groups  = [aws_security_group.task.id]
    assign_public_ip = false
  }

  dynamic "load_balancer" {
    for_each = local.attach_lb ? [1] : []

    content {
      target_group_arn = aws_lb_target_group.this[0].arn
      container_name   = var.container_name
      container_port   = var.container_port
    }
  }

  # Cloud Map registration, for a service reached by DNS name rather than
  # through the load balancer. A records on awsvpc tasks carry the ENI
  # address, so the registry ARN is the whole configuration.
  dynamic "service_registries" {
    for_each = var.service_registry_arn != null ? [1] : []

    content {
      registry_arn = var.service_registry_arn
    }
  }

  tags = {
    Name = var.name
  }

  lifecycle {
    # Autoscaling owns the task count after creation; without this, every apply
    # resets a scaled-out service back to desired_count.
    ignore_changes = [desired_count]
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
  desired_count   = var.desired_count

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

  deployment_minimum_healthy_percent = 100
  deployment_maximum_percent         = 200

  health_check_grace_period_seconds = local.attach_lb ? var.health_check_grace_period : null
  enable_execute_command            = var.enable_execute_command

  enable_ecs_managed_tags = true
  propagate_tags          = "SERVICE"

  availability_zone_rebalancing = "ENABLED"

  network_configuration {
    subnets          = var.subnet_ids
    security_groups  = [aws_security_group.task.id]
    assign_public_ip = false
  }

  dynamic "load_balancer" {
    for_each = local.attach_lb ? [1] : []

    content {
      target_group_arn = aws_lb_target_group.this[0].arn
      container_name   = var.container_name
      container_port   = var.container_port
    }
  }

  # Cloud Map registration, for a service reached by DNS name rather than
  # through the load balancer. A records on awsvpc tasks carry the ENI
  # address, so the registry ARN is the whole configuration.
  dynamic "service_registries" {
    for_each = var.service_registry_arn != null ? [1] : []

    content {
      registry_arn = var.service_registry_arn
    }
  }

  tags = {
    Name = var.name
  }

  lifecycle {
    # desired_count: as above, autoscaling owns it.
    #
    # task_definition: the service's own repository deploys new images with
    # `aws ecs update-service`, so the running revision is expected to be ahead
    # of the one Terraform last rendered. Without this, the next apply would
    # roll the service back to the digest in this repository — silently
    # reverting a deploy that already shipped.
    ignore_changes = [desired_count, task_definition]
  }

  # The listener rule must exist before the service registers targets.
  depends_on = [aws_lb_listener_rule.this]
}

locals {
  # One of the two counts is always zero, so exactly one element exists.
  service = one(concat(aws_ecs_service.this, aws_ecs_service.continuous))
}
# Autoscaling

resource "aws_appautoscaling_target" "this" {
  service_namespace  = "ecs"
  resource_id        = "service/${reverse(split("/", var.cluster_arn))[0]}/${local.service.name}"
  scalable_dimension = "ecs:service:DesiredCount"
  min_capacity       = var.autoscaling_min_capacity
  max_capacity       = var.autoscaling_max_capacity

  lifecycle {
    precondition {
      condition     = var.autoscaling_max_capacity >= var.autoscaling_min_capacity
      error_message = "autoscaling_max_capacity must be greater than or equal to autoscaling_min_capacity."
    }
  }
}

resource "aws_appautoscaling_policy" "cpu" {
  count = var.cpu_target != null ? 1 : 0

  name               = "${var.name}-cpu"
  policy_type        = "TargetTrackingScaling"
  service_namespace  = aws_appautoscaling_target.this.service_namespace
  resource_id        = aws_appautoscaling_target.this.resource_id
  scalable_dimension = aws_appautoscaling_target.this.scalable_dimension

  target_tracking_scaling_policy_configuration {
    target_value       = var.cpu_target
    scale_out_cooldown = var.scale_out_cooldown
    scale_in_cooldown  = var.scale_in_cooldown

    predefined_metric_specification {
      predefined_metric_type = "ECSServiceAverageCPUUtilization"
    }
  }
}

resource "aws_appautoscaling_policy" "memory" {
  count = var.memory_target != null ? 1 : 0

  name               = "${var.name}-memory"
  policy_type        = "TargetTrackingScaling"
  service_namespace  = aws_appautoscaling_target.this.service_namespace
  resource_id        = aws_appautoscaling_target.this.resource_id
  scalable_dimension = aws_appautoscaling_target.this.scalable_dimension

  target_tracking_scaling_policy_configuration {
    target_value       = var.memory_target
    scale_out_cooldown = var.scale_out_cooldown
    scale_in_cooldown  = var.scale_in_cooldown

    predefined_metric_specification {
      predefined_metric_type = "ECSServiceAverageMemoryUtilization"
    }
  }
}

resource "aws_appautoscaling_policy" "requests" {
  count = var.requests_per_target != null && local.attach_lb ? 1 : 0

  name               = "${var.name}-requests"
  policy_type        = "TargetTrackingScaling"
  service_namespace  = aws_appautoscaling_target.this.service_namespace
  resource_id        = aws_appautoscaling_target.this.resource_id
  scalable_dimension = aws_appautoscaling_target.this.scalable_dimension

  target_tracking_scaling_policy_configuration {
    target_value       = var.requests_per_target
    scale_out_cooldown = var.scale_out_cooldown
    scale_in_cooldown  = var.scale_in_cooldown

    predefined_metric_specification {
      predefined_metric_type = "ALBRequestCountPerTarget"
      # Positional and unvalidated at apply time: "<lb-suffix>/<tg-suffix>".
      # A wrong value creates cleanly and then never fires.
      resource_label = "${var.load_balancer_arn_suffix}/${aws_lb_target_group.this[0].arn_suffix}"
    }
  }

  lifecycle {
    precondition {
      condition     = var.load_balancer_arn_suffix != null
      error_message = "load_balancer_arn_suffix is required when requests_per_target is set: the ALBRequestCountPerTarget resource label cannot be built without it."
    }
  }
}
