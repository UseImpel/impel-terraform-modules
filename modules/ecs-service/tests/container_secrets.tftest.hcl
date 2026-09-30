# Execution-role secret grant contract. ReadSecrets must name the distinct set
# of secret ARNs across the primary container and every sidecar. Containers
# may share an environment-variable name for different secrets; an earlier
# version merged the maps by name and dropped all but one of those ARNs.
# Without a collision the set is exactly what callers had, so a ?ref= bump
# plans nothing.

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
  name                 = "secrets-test"
  cluster_arn          = "arn:aws:ecs:ap-southeast-1:123456789012:cluster/test"
  vpc_id               = "vpc-0test"
  subnet_ids           = ["subnet-0test"]
  container_name       = "app"
  container_image      = "public.ecr.aws/example/app:test"
  container_port       = 8080
  attach_load_balancer = false
}

run "no_secrets_renders_no_read_secrets_statement" {
  command = plan

  assert {
    condition     = length([for s in data.aws_iam_policy_document.execution.statement : s if s.sid == "ReadSecrets"]) == 0
    error_message = "With no container_secrets the execution role must not get a ReadSecrets statement."
  }
}

run "distinct_names_grant_the_same_arns_as_before" {
  command = plan

  variables {
    container_secrets = {
      DATABASE_URL = "arn:aws:secretsmanager:ap-southeast-1:123456789012:secret:app-db-AbCdEf:DATABASE_URL::"
      API_TOKEN    = "arn:aws:secretsmanager:ap-southeast-1:123456789012:secret:app-db-AbCdEf:API_TOKEN::"
    }
    sidecars = {
      adapter = {
        container_name  = "adapter"
        container_image = "public.ecr.aws/example/adapter:test"
        container_secrets = {
          REDIS_URL = "arn:aws:secretsmanager:ap-southeast-1:123456789012:secret:redis-GhIjKl"
        }
      }
    }
  }

  assert {
    condition = toset(one([for s in data.aws_iam_policy_document.execution.statement : s.resources if s.sid == "ReadSecrets"])) == toset([
      "arn:aws:secretsmanager:ap-southeast-1:123456789012:secret:app-db-AbCdEf",
      "arn:aws:secretsmanager:ap-southeast-1:123456789012:secret:redis-GhIjKl",
    ])
    error_message = "ReadSecrets must name each secret ARN once, with JSON-key suffixes stripped, across the primary container and sidecars."
  }
}

run "shared_variable_name_keeps_every_arn" {
  command = plan

  variables {
    container_secrets = {
      SERVICE_KEY = "arn:aws:secretsmanager:ap-southeast-1:123456789012:secret:console-key-AbCdEf:SERVICE_KEY::"
    }
    sidecars = {
      data = {
        container_name  = "data"
        container_image = "public.ecr.aws/example/data:test"
        container_secrets = {
          SERVICE_KEY = "arn:aws:secretsmanager:ap-southeast-1:123456789012:secret:data-key-GhIjKl:SERVICE_KEY::"
        }
      }
      ops = {
        container_name  = "ops"
        container_image = "public.ecr.aws/example/ops:test"
        container_secrets = {
          SERVICE_KEY  = "arn:aws:secretsmanager:ap-southeast-1:123456789012:secret:ops-key-MnOpQr:SERVICE_KEY::"
          DATABASE_URL = "arn:aws:secretsmanager:ap-southeast-1:123456789012:secret:console-key-AbCdEf:DATABASE_URL::"
        }
      }
    }
  }

  assert {
    condition = toset(one([for s in data.aws_iam_policy_document.execution.statement : s.resources if s.sid == "ReadSecrets"])) == toset([
      "arn:aws:secretsmanager:ap-southeast-1:123456789012:secret:console-key-AbCdEf",
      "arn:aws:secretsmanager:ap-southeast-1:123456789012:secret:data-key-GhIjKl",
      "arn:aws:secretsmanager:ap-southeast-1:123456789012:secret:ops-key-MnOpQr",
    ])
    error_message = "Containers sharing an environment-variable name must each keep their own secret ARN in ReadSecrets."
  }

  assert {
    condition     = length(one([for s in data.aws_iam_policy_document.execution.statement : s.resources if s.sid == "ReadSecrets"])) == 3
    error_message = "A secret named by several containers or JSON keys must be granted once."
  }
}
