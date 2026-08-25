# Secrets Manager secret whose shape Terraform manages and whose values it does
# not. Services reference individual keys as secret-arn:KEY::, so every key a
# task definition names must exist or the task fails to start.
#
# Terraform manages the secret and nothing inside it. An earlier version also
# created a placeholder aws_secretsmanager_secret_version holding empty strings,
# with ignore_changes on the value. That was wrong in a way only CI could show:
# ignore_changes suppresses the diff but not the refresh, so every plan called
# secretsmanager:GetSecretValue. AWS's ReadOnlyAccess deliberately withholds
# that action, so the plan role could not read it and every dev plan failed.
#
# Granting the permission would have let a read-only CI role read every secret
# in the account to work around a resource that existed only to write empty
# strings. Removing the resource is both the smaller change and the safer one:
# the plan role never needs secret read access, and no secret value can reach a
# plan log or the state file.
#
# The keys variable is still the source of truth for what a service expects —
# outputs.tf turns it into the secret-arn:KEY:: references the task definition
# consumes, and seed_command below prints how to populate them.

resource "aws_secretsmanager_secret" "this" {
  #checkov:skip=CKV2_AWS_57:Rotation needs a service-specific rotation Lambda that does not exist yet; these are seeded and rotated out of band.
  name                           = var.name
  description                    = var.description
  kms_key_id                     = var.kms_key_arn
  recovery_window_in_days        = var.recovery_window_days
  force_overwrite_replica_secret = false

  tags = {
    Name = var.name
  }
}

# Drops the placeholder version from state without touching the live secret.
# A plain resource removal would destroy the version, and by the time this
# lands an operator may already have seeded real values into it.
removed {
  from = aws_secretsmanager_secret_version.placeholder

  lifecycle {
    destroy = false
  }
}
