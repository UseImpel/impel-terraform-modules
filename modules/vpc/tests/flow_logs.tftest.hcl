# Offline policy-input contract; mocked JSON is not used as proof of IAM access.
mock_provider "aws" {
  override_during = plan
  mock_data "aws_iam_policy_document" {
    defaults = {
      json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}"
    }
  }
  mock_resource "aws_cloudwatch_log_group" {
    defaults = {
      arn = "arn:aws:logs:ap-southeast-1:123456789012:log-group:/vpc/flow-test"
    }
  }
}

variables {
  name                 = "flow-test"
  cidr_block           = "10.10.0.0/16"
  availability_zones   = ["ap-southeast-1a", "ap-southeast-1b"]
  public_subnet_cidrs  = ["10.10.0.0/24", "10.10.1.0/24"]
  private_subnet_cidrs = ["10.10.2.0/24", "10.10.3.0/24"]
  enable_flow_logs     = true
}

run "group_and_stream_authorization" {
  command = plan

  assert {
    condition = anytrue([for s in data.aws_iam_policy_document.flow_logs[0].statement :
      s.effect == "Allow" && toset(s.actions) == toset(["logs:DescribeLogStreams"]) &&
      toset(s.resources) == toset([aws_cloudwatch_log_group.flow_logs[0].arn])
    ])
    error_message = "DescribeLogStreams must have an exact, bare log-group ARN grant."
  }

  assert {
    condition = anytrue([for s in data.aws_iam_policy_document.flow_logs[0].statement :
      s.effect == "Allow" && toset(s.actions) == toset(["logs:CreateLogStream", "logs:PutLogEvents", "logs:DescribeLogStreams"]) &&
      toset(s.resources) == toset(["${aws_cloudwatch_log_group.flow_logs[0].arn}:*"])
    ])
    error_message = "Retain the existing stream grant throughout AWS's regional rollout."
  }

  assert {
    condition     = length(data.aws_iam_policy_document.flow_logs[0].statement) == 2
    error_message = "Do not broaden flow-log permissions beyond the two scoped grants."
  }
}
