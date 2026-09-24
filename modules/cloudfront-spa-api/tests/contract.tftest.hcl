mock_provider "aws" {
  override_during = plan
  mock_data "aws_caller_identity" {
    defaults = { account_id = "123456789012" }
  }
  mock_data "aws_cloudfront_cache_policy" {
    defaults = { id = "cache-policy" }
  }
  mock_data "aws_cloudfront_origin_request_policy" {
    defaults = { id = "origin-policy" }
  }
  mock_data "aws_cloudfront_response_headers_policy" {
    defaults = { id = "headers-policy" }
  }
}

variables {
  name                   = "tasks-web-dev"
  bucket_name            = "tasks-web-dev-123456789012"
  aliases                = ["tasks.dev.example.com"]
  certificate_arn        = "arn:aws:acm:us-east-1:123456789012:certificate/example"
  api_origin_domain_name = "tasks-origin.dev.example.com"
}

run "edge_shape" {
  command = plan

  assert {
    condition     = aws_s3_bucket_public_access_block.frontend.block_public_acls && aws_s3_bucket_public_access_block.frontend.restrict_public_buckets
    error_message = "The SPA bucket must remain private."
  }
  assert {
    condition     = aws_cloudfront_distribution.this.enabled
    error_message = "CloudFront must be enabled for the canonical alias."
  }
}
