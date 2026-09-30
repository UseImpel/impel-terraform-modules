# Capacity placement contract. The default path must render the exact
# single-provider block callers had before capacity_provider_strategy existed,
# with force_new_deployment left unset, so a ?ref= bump plans nothing. A mixed
# strategy renders every entry and turns force_new_deployment on, which AWS
# provider 6.x requires to change a strategy on an existing service in place.

mock_provider "aws" {
  override_during = plan

  mock_data "aws_region" {
    defaults = {
      id     = "ap-southeast-1"
      name   = "ap-southeast-1"
      region = "ap-southeast-1"
    }
  }

  mock_data "aws_iam_policy_document" {
    defaults = {
      json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}"
    }
  }
}

variables {
  name                 = "capacity-test"
  cluster_arn          = "arn:aws:ecs:ap-southeast-1:123456789012:cluster/test"
  vpc_id               = "vpc-0test"
  subnet_ids           = ["subnet-0test"]
  container_name       = "app"
  container_image      = "public.ecr.aws/example/app:test"
  container_port       = 8080
  attach_load_balancer = false
}

run "default_renders_the_single_provider_block_unchanged" {
  command = plan

  assert {
    condition = (
      length(aws_ecs_service.this[0].capacity_provider_strategy) == 1 &&
      one(aws_ecs_service.this[0].capacity_provider_strategy).capacity_provider == "FARGATE" &&
      one(aws_ecs_service.this[0].capacity_provider_strategy).weight == 1 &&
      one(aws_ecs_service.this[0].capacity_provider_strategy).base == 0
    )
    error_message = "With no capacity_provider_strategy the service must keep the FARGATE weight 1 base 0 block it always had."
  }

  assert {
    condition     = aws_ecs_service.this[0].force_new_deployment == null
    error_message = "force_new_deployment must stay unset on the default path, or every existing caller sees a plan diff on upgrade."
  }
}

run "single_capacity_provider_still_selects_spot" {
  command = plan

  variables {
    capacity_provider = "FARGATE_SPOT"
  }

  assert {
    condition     = one(aws_ecs_service.this[0].capacity_provider_strategy).capacity_provider == "FARGATE_SPOT"
    error_message = "capacity_provider must still pick the provider when no strategy is given."
  }

  assert {
    condition     = aws_ecs_service.this[0].force_new_deployment == null
    error_message = "capacity_provider alone must not set force_new_deployment."
  }
}

run "mixed_strategy_keeps_an_on_demand_base_and_bursts_on_spot" {
  command = plan

  variables {
    capacity_provider_strategy = [
      { capacity_provider = "FARGATE", weight = 0, base = 1 },
      { capacity_provider = "FARGATE_SPOT", weight = 1 },
    ]
  }

  assert {
    condition     = length(aws_ecs_service.this[0].capacity_provider_strategy) == 2
    error_message = "Both strategy entries must render."
  }

  assert {
    condition = anytrue([
      for s in aws_ecs_service.this[0].capacity_provider_strategy :
      s.capacity_provider == "FARGATE" && s.weight == 0 && s.base == 1
    ])
    error_message = "The on-demand entry must carry base 1 and weight 0."
  }

  assert {
    condition = anytrue([
      for s in aws_ecs_service.this[0].capacity_provider_strategy :
      s.capacity_provider == "FARGATE_SPOT" && s.weight == 1 && s.base == 0
    ])
    error_message = "The Spot entry must default base to 0."
  }

  assert {
    condition     = aws_ecs_service.this[0].force_new_deployment == true
    error_message = "A custom strategy must set force_new_deployment, or AWS provider 6.x refuses the in-place strategy change."
  }
}

run "mixed_strategy_applies_to_the_continuous_deployment_variant" {
  command = plan

  variables {
    continuous_deployment = true
    capacity_provider_strategy = [
      { capacity_provider = "FARGATE", weight = 0, base = 1 },
      { capacity_provider = "FARGATE_SPOT", weight = 1 },
    ]
  }

  assert {
    condition     = length(aws_ecs_service.this) == 0 && length(aws_ecs_service.continuous[0].capacity_provider_strategy) == 2
    error_message = "The continuous-deployment service must render the same strategy."
  }

  assert {
    condition     = aws_ecs_service.continuous[0].force_new_deployment == true
    error_message = "The continuous-deployment service must also set force_new_deployment."
  }
}

run "strategy_supersedes_capacity_provider" {
  command = plan

  variables {
    capacity_provider = "FARGATE"
    capacity_provider_strategy = [
      { capacity_provider = "FARGATE_SPOT", weight = 1 },
    ]
  }

  assert {
    condition     = one(aws_ecs_service.this[0].capacity_provider_strategy).capacity_provider == "FARGATE_SPOT"
    error_message = "capacity_provider must be ignored when capacity_provider_strategy is set."
  }
}

run "autoscaling_cooldowns_pass_through" {
  command = plan

  variables {
    cpu_target         = 60
    memory_target      = 75
    scale_out_cooldown = 60
    scale_in_cooldown  = 300
  }

  assert {
    condition = (
      aws_appautoscaling_policy.cpu[0].target_tracking_scaling_policy_configuration[0].scale_out_cooldown == 60 &&
      aws_appautoscaling_policy.cpu[0].target_tracking_scaling_policy_configuration[0].scale_in_cooldown == 300 &&
      aws_appautoscaling_policy.memory[0].target_tracking_scaling_policy_configuration[0].scale_in_cooldown == 300
    )
    error_message = "scale_out_cooldown and scale_in_cooldown must reach every target-tracking policy."
  }
}

run "no_scaling_policies_when_every_target_is_null" {
  command = plan

  variables {
    cpu_target = null
  }

  assert {
    condition     = length(aws_appautoscaling_policy.cpu) == 0 && length(aws_appautoscaling_policy.memory) == 0 && length(aws_appautoscaling_policy.requests) == 0
    error_message = "Null targets must create no scaling policies (and so no CloudWatch alarms)."
  }
}

run "rejects_an_unknown_provider" {
  command = plan

  variables {
    capacity_provider_strategy = [{ capacity_provider = "EC2", weight = 1 }]
  }

  expect_failures = [var.capacity_provider_strategy]
}

run "rejects_a_duplicate_provider" {
  command = plan

  variables {
    capacity_provider_strategy = [
      { capacity_provider = "FARGATE_SPOT", weight = 1 },
      { capacity_provider = "FARGATE_SPOT", weight = 2 },
    ]
  }

  expect_failures = [var.capacity_provider_strategy]
}

run "rejects_two_bases" {
  command = plan

  variables {
    capacity_provider_strategy = [
      { capacity_provider = "FARGATE", weight = 1, base = 1 },
      { capacity_provider = "FARGATE_SPOT", weight = 1, base = 1 },
    ]
  }

  expect_failures = [var.capacity_provider_strategy]
}

run "rejects_all_zero_weights" {
  command = plan

  variables {
    capacity_provider_strategy = [
      { capacity_provider = "FARGATE", weight = 0, base = 1 },
      { capacity_provider = "FARGATE_SPOT", weight = 0 },
    ]
  }

  expect_failures = [var.capacity_provider_strategy]
}
