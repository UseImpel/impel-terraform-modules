mock_provider "aws" {
  override_during = plan
  mock_data "aws_iam_policy_document" {
    defaults = { json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}" }
  }
  mock_data "aws_caller_identity" {
    defaults = { account_id = "123456789012" }
  }
}

variables {
  name              = "tasks-web-dev-github"
  github_repository = "UseImpel/impel-tasks"
  deploy_branch     = "dev"
  bucket_arn        = "arn:aws:s3:::tasks-web-dev-123456789012"
  distribution_arn  = "arn:aws:cloudfront::123456789012:distribution/ABC"
}

run "least_privilege_shape" {
  command = plan

  assert {
    condition     = aws_iam_role_policy.deploy.policy != ""
    error_message = "The static-site role must have an inline deployment policy."
  }
  assert {
    condition     = length(data.aws_iam_policy_document.trust.statement) == 1
    error_message = "The role must have one restricted GitHub OIDC trust statement."
  }
}
