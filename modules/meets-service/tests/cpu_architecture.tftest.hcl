# CPU architecture contract. The default must render the X86_64 runtime
# platform the meets task definition always had, so a ?ref= bump plans no new
# revision (and so no stop-then-start redeploy). ARM64 must reach the task
# definition, and must be refused on Fargate platform versions older than 1.4.0.

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
  name                   = "meets-arch-test"
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
    condition     = one(aws_ecs_task_definition.this.runtime_platform).cpu_architecture == "ARM64"
    error_message = "cpu_architecture = ARM64 must render an ARM64 runtime platform."
  }
}

run "arm64_on_fargate_spot" {
  command = plan

  variables {
    cpu_architecture     = "ARM64"
    capacity_provider    = "FARGATE_SPOT"
    force_new_deployment = true
  }

  assert {
    condition = (
      one(aws_ecs_task_definition.this.runtime_platform).cpu_architecture == "ARM64" &&
      [for s in aws_ecs_service.this[0].capacity_provider_strategy : s.capacity_provider] == ["FARGATE_SPOT"]
    )
    error_message = "ARM64 must combine with FARGATE_SPOT."
  }
}

run "rejects_an_unknown_architecture" {
  command = plan

  variables {
    cpu_architecture = "AARCH64"
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
