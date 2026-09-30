# CPU architecture contract. The default must render the X86_64 runtime
# platform every task definition had before cpu_architecture existed, so a
# ?ref= bump plans no new task definition revision. ARM64 must reach the task
# definition on either capacity provider, and must be refused on Fargate
# platform versions older than 1.4.0, which run X86_64 only.

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
  name                 = "arch-test"
  cluster_arn          = "arn:aws:ecs:ap-southeast-1:123456789012:cluster/test"
  vpc_id               = "vpc-0test"
  subnet_ids           = ["subnet-0test"]
  container_name       = "app"
  container_image      = "public.ecr.aws/example/app:test"
  container_port       = 8080
  attach_load_balancer = false
}

run "default_keeps_x86_64" {
  command = plan

  assert {
    condition = (
      one(aws_ecs_task_definition.this.runtime_platform).cpu_architecture == "X86_64" &&
      one(aws_ecs_task_definition.this.runtime_platform).operating_system_family == "LINUX"
    )
    error_message = "With no cpu_architecture the task definition must keep the X86_64/LINUX runtime platform it always had."
  }
}

run "arm64_reaches_the_task_definition" {
  command = plan

  variables {
    cpu_architecture = "ARM64"
  }

  assert {
    condition = (
      one(aws_ecs_task_definition.this.runtime_platform).cpu_architecture == "ARM64" &&
      one(aws_ecs_task_definition.this.runtime_platform).operating_system_family == "LINUX"
    )
    error_message = "cpu_architecture = ARM64 must render an ARM64/LINUX runtime platform."
  }
}

run "arm64_on_fargate_spot_with_a_pinned_platform" {
  command = plan

  variables {
    cpu_architecture           = "ARM64"
    platform_version           = "1.4.0"
    capacity_provider_strategy = [{ capacity_provider = "FARGATE_SPOT", weight = 1 }]
  }

  assert {
    condition = (
      one(aws_ecs_task_definition.this.runtime_platform).cpu_architecture == "ARM64" &&
      one(aws_ecs_service.this[0].capacity_provider_strategy).capacity_provider == "FARGATE_SPOT" &&
      aws_ecs_service.this[0].platform_version == "1.4.0"
    )
    error_message = "ARM64 must combine with FARGATE_SPOT on platform 1.4.0."
  }
}

run "arm64_with_continuous_deployment" {
  command = plan

  variables {
    cpu_architecture      = "ARM64"
    continuous_deployment = true
  }

  assert {
    condition     = length(aws_ecs_service.continuous) == 1 && one(aws_ecs_task_definition.this.runtime_platform).cpu_architecture == "ARM64"
    error_message = "The continuous-deployment variant shares the one task definition, which must carry ARM64."
  }
}

run "rejects_an_unknown_architecture" {
  command = plan

  variables {
    cpu_architecture = "arm64"
  }

  expect_failures = [var.cpu_architecture]
}

run "rejects_arm64_on_a_pre_1_4_platform" {
  command = plan

  variables {
    cpu_architecture = "ARM64"
    platform_version = "1.3.0"
  }

  expect_failures = [var.cpu_architecture]
}
