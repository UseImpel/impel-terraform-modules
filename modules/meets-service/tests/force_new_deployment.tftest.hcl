# The AWS provider fails the plan when an existing service's capacity provider
# changes and force_new_deployment is not true. Callers that never set the
# variable must leave the argument unset, so bumping the module plans no change.

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
  name                   = "meets-fnd-test"
  cluster_arn            = "arn:aws:ecs:ap-southeast-1:123456789012:cluster/test"
  vpc_id                 = "vpc-0test"
  subnet_ids             = ["subnet-0test"]
  cpu                    = 512
  memory                 = 1024
  primary_container_name = "gateway"
  attach_load_balancer   = false

  containers = {
    gateway = {
      image  = "public.ecr.aws/example/gateway:test"
      cpu    = 256
      memory = 512
      port   = 8000
    }
  }
}

run "default_leaves_force_new_deployment_unset" {
  command = plan

  assert {
    condition     = aws_ecs_service.this[0].force_new_deployment == null
    error_message = "force_new_deployment must stay unset by default, or every existing caller plans a diff."
  }

  assert {
    condition = [for s in aws_ecs_service.this[0].capacity_provider_strategy : s] == [
      { capacity_provider = "FARGATE", weight = 1, base = 0 },
    ]
    error_message = "The default strategy must stay the single FARGATE entry."
  }
}

run "spot_switch_with_force_new_deployment" {
  command = plan

  variables {
    capacity_provider    = "FARGATE_SPOT"
    force_new_deployment = true
  }

  assert {
    condition = [for s in aws_ecs_service.this[0].capacity_provider_strategy : s] == [
      { capacity_provider = "FARGATE_SPOT", weight = 1, base = 0 },
    ]
    error_message = "capacity_provider must select FARGATE_SPOT."
  }

  assert {
    condition     = aws_ecs_service.this[0].force_new_deployment == true
    error_message = "force_new_deployment = true must reach the service."
  }
}

run "continuous_deployment_variant_gets_force_new_deployment" {
  command = plan

  variables {
    continuous_deployment = true
    capacity_provider     = "FARGATE_SPOT"
    force_new_deployment  = true
  }

  assert {
    condition     = length(aws_ecs_service.this) == 0 && aws_ecs_service.continuous[0].force_new_deployment == true
    error_message = "The continuous-deployment service must carry force_new_deployment too."
  }
}
