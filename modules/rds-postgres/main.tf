# Provisioned RDS for PostgreSQL: one single-AZ instance, per-instance CMK,
# postgresql log export, credentials in Secrets Manager.
#
# The interface deliberately mirrors modules/aurora-serverless so a caller can
# stand this up beside a cluster and cut over by changing which module's
# outputs it reads. The one output that is NOT interchangeable is `endpoint` --
# see outputs.tf.

data "aws_partition" "current" {}

locals {
  # Created ahead of RDS, which would otherwise create it set to never expire.
  log_group_name = "/aws/rds/instance/${var.name}/postgresql"

  # postgres17, not aurora-postgresql17. Engine-family parameter groups are not
  # interchangeable and RDS rejects the wrong family at create time.
  parameter_group_family = "postgres${split(".", var.engine_version)[0]}"
}

resource "aws_kms_key" "this" {
  #checkov:skip=CKV2_AWS_64:The default key policy grants the account root, which is what lets IAM policies govern access. A bespoke policy would have to re-grant RDS, Secrets Manager and Performance Insights by hand.
  description             = "Encryption at rest for the ${var.name} RDS instance."
  enable_key_rotation     = true
  deletion_window_in_days = 30

  tags = {
    Name = "${var.name}-database"
  }
}

resource "aws_kms_alias" "this" {
  name          = "alias/${var.name}-database"
  target_key_id = aws_kms_key.this.key_id
}

resource "aws_db_subnet_group" "this" {
  name       = var.name
  subnet_ids = var.subnet_ids

  tags = {
    Name = var.name
  }
}

resource "aws_security_group" "this" {
  name        = "${var.name}-database"
  description = "RDS ${var.name} accepts traffic only from explicit client security groups."
  vpc_id      = var.vpc_id

  tags = {
    Name = "${var.name}-database"
  }
}

# Source security groups only; there is deliberately no CIDR variable.
resource "aws_vpc_security_group_ingress_rule" "postgres" {
  for_each = toset(var.allowed_security_group_ids)

  security_group_id = aws_security_group.this.id
  description       = "PostgreSQL from ${each.value}."

  referenced_security_group_id = each.value
  from_port                    = 5432
  to_port                      = 5432
  ip_protocol                  = "tcp"
}

resource "aws_db_parameter_group" "this" {
  name        = var.name
  family      = local.parameter_group_family
  description = "Instance parameters for ${var.name}."

  dynamic "parameter" {
    for_each = var.instance_parameters

    content {
      name  = parameter.key
      value = parameter.value
    }
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_cloudwatch_log_group" "postgresql" {
  #checkov:skip=CKV_AWS_158:RDS writes to this group through a service-linked path that does not support a CMK; the group is created ahead of RDS purely to enforce retention.
  #checkov:skip=CKV_AWS_338:Retention is var.log_retention_days. A year of dev database logs is cost with no reader.
  name              = local.log_group_name
  retention_in_days = var.log_retention_days
}

resource "aws_db_instance" "this" {
  #checkov:skip=CKV_AWS_157:Multi-AZ is var.multi_az. A standby doubles the instance charge; dev runs single-AZ deliberately.
  #checkov:skip=CKV_AWS_161:IAM database authentication is enabled below, but the master password remains the path every current consumer uses.
  #checkov:skip=CKV_AWS_293:Deletion protection is var.deletion_protection, true by default. Dev sets it false so the environment can be destroyed.
  #checkov:skip=CKV_AWS_118:Enhanced monitoring is var.monitoring_interval, off by default for the same reason as in aurora-serverless: per-second OS metrics on a db.t4g.micro dev instance cost more than they reveal. Prod sets the interval and gets the role.
  #checkov:skip=CKV_AWS_226:auto_minor_version_upgrade is false deliberately -- see the argument below. engine_version pins major.minor, so RDS taking a minor on its own is permanent drift on every subsequent plan rather than a silent improvement. Minors are taken by bumping the variable, which is a reviewed change.
  #checkov:skip=CKV_AWS_211:The check is older than the CA it is rejecting. CI pins bridgecrew/checkov:2.0.930, which predates rds-ca-rsa2048-g1 and recognises only rds-ca-2019 as modern -- and rds-ca-2019 expired in August 2024. describe-certificates reports the pinned CA valid until 2061, and it is what every Aurora instance in the estate already presents. Satisfying this check literally would mean pinning an expired CA.
  #checkov:skip=CKV2_AWS_30:Query logging needs log_statement, which logs every statement including its arguments. Enable per instance via var.instance_parameters where the data warrants it.
  #checkov:skip=CKV2_AWS_60:Automated backups are configured through backup_retention_period. An AWS Backup plan is an estate-wide decision, not a per-instance one.
  identifier = var.name
  engine     = "postgres"
  # A major.minor version pins the minor too, so auto_minor_version_upgrade
  # would fight this value on every plan. Both are set deliberately: see the
  # auto_minor_version_upgrade argument below.
  engine_version = var.engine_version
  instance_class = var.instance_class
  db_name        = var.database_name
  port           = 5432

  username = var.master_username
  # RDS generates, stores and rotates the password, so no credential reaches
  # Terraform state.
  manage_master_user_password   = true
  master_user_secret_kms_key_id = aws_kms_key.this.arn

  db_subnet_group_name   = aws_db_subnet_group.this.name
  parameter_group_name   = aws_db_parameter_group.this.name
  vpc_security_group_ids = [aws_security_group.this.id]
  publicly_accessible    = false

  # gp3 at 20 GiB carries 3000 IOPS and 125 MiB/s at no extra charge, and --
  # unlike Aurora -- there is no per-request StorageIOUsage line. Storage
  # autoscaling is the cheap insurance against a dev volume filling silently.
  storage_type          = "gp3"
  allocated_storage     = var.allocated_storage
  max_allocated_storage = var.max_allocated_storage > 0 ? var.max_allocated_storage : null
  storage_encrypted     = true
  kms_key_id            = aws_kms_key.this.arn

  # Pinned, not inherited from the account default: a client that validates the
  # server certificate fails to connect against an unexpected chain, and that
  # failure reads as a network problem rather than a certificate one.
  ca_cert_identifier = var.ca_cert_identifier

  multi_az                     = var.multi_az
  backup_retention_period      = var.backup_retention_days
  backup_window                = "17:00-18:00" # 01:00-02:00 SGT
  maintenance_window           = "sun:18:00-sun:19:00"
  copy_tags_to_snapshot        = true
  performance_insights_enabled = var.performance_insights_enabled
  # Performance Insights retention is not optional when the feature is on: the
  # provider sends 7 (the free tier) only if told to, and RDS bills anything
  # longer.
  performance_insights_retention_period = var.performance_insights_enabled ? 7 : null
  performance_insights_kms_key_id       = var.performance_insights_enabled ? aws_kms_key.this.arn : null

  monitoring_interval = var.monitoring_interval
  monitoring_role_arn = var.monitoring_interval > 0 ? aws_iam_role.monitoring[0].arn : null

  deletion_protection       = var.deletion_protection
  skip_final_snapshot       = var.skip_final_snapshot
  final_snapshot_identifier = var.skip_final_snapshot ? null : "${var.name}-final"
  apply_immediately         = var.apply_immediately

  # False, unlike the Aurora module. engine_version here is a full major.minor
  # string, and RDS upgrading the minor out from under it would show up as
  # permanent drift on the next plan. Bump var.engine_version to take a minor.
  auto_minor_version_upgrade = false

  enabled_cloudwatch_logs_exports     = ["postgresql"]
  iam_database_authentication_enabled = true

  tags = {
    Name = var.name
  }

  depends_on = [aws_cloudwatch_log_group.postgresql]
}

# Stretches the interval of a rotation this module cannot turn off.
#
# RDS owns the master credential rotation schedule (seven days). No argument on
# aws_db_instance disables it, and CancelRotateSecret is refused because the
# secret's OwningService is rds. That call is also this resource's destroy
# path, which is why it is created only when a caller asks -- adding then
# removing it would leave a destroy that cannot succeed.
#
# The interval is therefore the only lever, and 999 days is the Secrets Manager
# maximum. A dev account sets that to opt out in practice; prod leaves the
# variable null and keeps the seven-day default.
#
# rotate_immediately is false on purpose. It defaults to true, and true here
# would rotate the password the moment this applies -- the exact failure this
# change exists to make rare. ECS resolves a secrets block only when a task
# starts, so a rotation leaves every running task holding a credential the
# instance no longer accepts until the service is redeployed.
#
# No rotation_lambda_arn: it is optional in the provider schema and must be
# omitted for a managed secret, which RDS rotates without a function.
resource "aws_secretsmanager_secret_rotation" "master_password" {
  #checkov:skip=CKV_AWS_304:A caller that sets this variable is lengthening the interval, and the value it is likely to set -- 999, the AWS maximum -- is by definition more than 90 days. The check is right that this weakens rotation; that is the deliberate trade for a dev account whose tasks are stranded by every rotation. Prod leaves master_password_rotation_days null, creates none of this, and keeps RDS's seven days.
  count = var.master_password_rotation_days == null ? 0 : 1

  secret_id          = aws_db_instance.this.master_user_secret[0].secret_arn
  rotate_immediately = false

  rotation_rules {
    automatically_after_days = var.master_password_rotation_days
  }
}

data "aws_iam_policy_document" "monitoring_assume" {
  count = var.monitoring_interval > 0 ? 1 : 0

  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["monitoring.rds.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "monitoring" {
  count = var.monitoring_interval > 0 ? 1 : 0

  name               = "${var.name}-rds-monitoring"
  assume_role_policy = data.aws_iam_policy_document.monitoring_assume[0].json
}

resource "aws_iam_role_policy_attachment" "monitoring" {
  count = var.monitoring_interval > 0 ? 1 : 0

  role       = aws_iam_role.monitoring[0].name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/service-role/AmazonRDSEnhancedMonitoringRole"
}
