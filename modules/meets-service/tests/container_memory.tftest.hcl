# The meets task's only hard memory cap is the task-level limit. Per-container
# memory is a soft ECS reservation, which lets one container borrow capacity
# another container in the shared task is not using.

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
  name                   = "meets-memory-test"
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

run "container_memory_is_a_soft_reservation" {
  command = plan

  module {
    source = "./"
  }

  assert {
    condition     = jsondecode(aws_ecs_task_definition.this.container_definitions)[0].memoryReservation == 512
    error_message = "Per-container memory must render as ECS memoryReservation."
  }

  assert {
    condition     = !contains(keys(jsondecode(aws_ecs_task_definition.this.container_definitions)[0]), "memory")
    error_message = "Meets containers must not receive a container-level hard memory limit."
  }

  assert {
    condition     = aws_ecs_task_definition.this.memory == "1024"
    error_message = "The task-level memory setting remains the sole hard cap."
  }
}

run "container_memory_reservation_cannot_exceed_task_memory" {
  command = plan

  module {
    source = "./"
  }

  variables {
    containers = {
      gateway = {
        image  = "public.ecr.aws/example/gateway:test"
        cpu    = 256
        memory = 1025
        port   = 8000
      }
    }
  }

  expect_failures = [aws_ecs_task_definition.this]
}

run "container_definitions_are_exported_for_consumer_contracts" {
  command = plan

  module {
    source = "./"
  }

  assert {
    condition     = output.container_definitions[0].memoryReservation == 512
    error_message = "Consumers must be able to assert the soft-memory contract from module outputs."
  }
}
