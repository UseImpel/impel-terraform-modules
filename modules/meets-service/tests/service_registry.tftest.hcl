# Cloud Map registration is opt-in. Callers that never set service_registry_arn
# must render no service_registries block, so bumping the module plans no change.

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
  name                   = "meets-registry-test"
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

run "default_registers_nothing" {
  command = plan

  assert {
    condition     = length(aws_ecs_service.this[0].service_registries) == 0
    error_message = "No service_registries block may render unless service_registry_arn is set."
  }
}

run "registry_arn_reaches_the_service" {
  command = plan

  variables {
    service_registry_arn = "arn:aws:servicediscovery:ap-southeast-1:123456789012:service/srv-0123456789abcdef"
  }

  assert {
    condition     = [for r in aws_ecs_service.this[0].service_registries : r.registry_arn] == ["arn:aws:servicediscovery:ap-southeast-1:123456789012:service/srv-0123456789abcdef"]
    error_message = "service_registry_arn must render one service_registries block carrying that ARN."
  }
}

run "continuous_deployment_variant_registers_too" {
  command = plan

  variables {
    continuous_deployment = true
    service_registry_arn  = "arn:aws:servicediscovery:ap-southeast-1:123456789012:service/srv-0123456789abcdef"
  }

  assert {
    condition     = length(aws_ecs_service.this) == 0 && [for r in aws_ecs_service.continuous[0].service_registries : r.registry_arn] == ["arn:aws:servicediscovery:ap-southeast-1:123456789012:service/srv-0123456789abcdef"]
    error_message = "The continuous-deployment service must register in Cloud Map too."
  }
}

run "rejects_a_non_cloud_map_arn" {
  command = plan

  variables {
    service_registry_arn = "arn:aws:servicediscovery:ap-southeast-1:123456789012:namespace/ns-0123456789abcdef"
  }

  expect_failures = [var.service_registry_arn]
}
