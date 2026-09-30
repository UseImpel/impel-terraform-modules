# Lifecycle retention contract. The default (and any number) must render the
# exact expire-objects rule callers had before retention_days became nullable,
# so a ?ref= bump plans nothing. retention_days = null keeps objects and
# noncurrent versions forever: the same rule, with only the multipart-upload
# abort left in it.

mock_provider "aws" {
  override_during = plan

  mock_data "aws_iam_policy_document" {
    defaults = {
      json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}"
    }
  }
}

variables {
  name   = "retention-test-123456789012"
  prefix = "bifrost/logs"
}

run "default_expires_at_14_days_unchanged" {
  command = plan

  assert {
    condition     = one(aws_s3_bucket_lifecycle_configuration.this.rule).id == "expire-objects"
    error_message = "The rule id must stay expire-objects."
  }

  assert {
    condition     = one(one(aws_s3_bucket_lifecycle_configuration.this.rule).expiration).days == 14
    error_message = "The default must keep expiring current objects at 14 days."
  }

  assert {
    condition     = one(one(aws_s3_bucket_lifecycle_configuration.this.rule).noncurrent_version_expiration).noncurrent_days == 14
    error_message = "The default must keep expiring noncurrent versions at 14 days."
  }

  assert {
    condition     = one(one(aws_s3_bucket_lifecycle_configuration.this.rule).abort_incomplete_multipart_upload).days_after_initiation == 7
    error_message = "Incomplete multipart uploads must still abort after 7 days."
  }

  assert {
    condition     = one(one(aws_s3_bucket_lifecycle_configuration.this.rule).filter).prefix == "bifrost/logs/"
    error_message = "The lifecycle filter must stay scoped to the prefix."
  }
}

run "explicit_days_apply_to_both_expirations" {
  command = plan

  variables {
    retention_days = 3650
  }

  assert {
    condition = (
      one(one(aws_s3_bucket_lifecycle_configuration.this.rule).expiration).days == 3650 &&
      one(one(aws_s3_bucket_lifecycle_configuration.this.rule).noncurrent_version_expiration).noncurrent_days == 3650
    )
    error_message = "retention_days must set both the current and the noncurrent expiration."
  }
}

run "null_keeps_objects_forever" {
  command = plan

  variables {
    retention_days = null
  }

  assert {
    condition     = one(aws_s3_bucket_lifecycle_configuration.this.rule).id == "expire-objects"
    error_message = "Switching to null must keep the same rule id, so the change is in place."
  }

  assert {
    condition     = one(aws_s3_bucket_lifecycle_configuration.this.rule).status == "Enabled"
    error_message = "The rule must stay enabled for the multipart-upload abort."
  }

  assert {
    condition     = length(one(aws_s3_bucket_lifecycle_configuration.this.rule).expiration) == 0
    error_message = "retention_days = null must not expire current objects."
  }

  assert {
    condition     = length(one(aws_s3_bucket_lifecycle_configuration.this.rule).noncurrent_version_expiration) == 0
    error_message = "retention_days = null must not expire noncurrent versions."
  }

  assert {
    condition     = one(one(aws_s3_bucket_lifecycle_configuration.this.rule).abort_incomplete_multipart_upload).days_after_initiation == 7
    error_message = "retention_days = null must keep aborting incomplete multipart uploads after 7 days."
  }

  assert {
    condition     = aws_s3_bucket_versioning.this.versioning_configuration[0].status == "Enabled"
    error_message = "Versioning must stay enabled."
  }
}

run "zero_days_is_rejected" {
  command = plan

  variables {
    retention_days = 0
  }

  expect_failures = [var.retention_days]
}

run "more_than_3650_days_is_rejected" {
  command = plan

  variables {
    retention_days = 3651
  }

  expect_failures = [var.retention_days]
}
