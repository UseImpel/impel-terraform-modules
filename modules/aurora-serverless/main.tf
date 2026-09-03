# Aurora PostgreSQL Serverless v2: one db.serverless writer, per-cluster CMK,
# postgresql log export, credentials in Secrets Manager.

data "aws_partition" "current" {}

locals {
  # Created ahead of RDS, which would otherwise create it set to never expire.
  log_group_name = "/aws/rds/cluster/${var.name}/postgresql"
}

resource "aws_kms_key" "this" {
  #checkov:skip=CKV2_AWS_64:The default key policy grants the account root, which is what lets IAM policies govern access. A bespoke policy would have to re-grant RDS, Secrets Manager and Performance Insights by hand.
  description             = "Encryption at rest for the ${var.name} Aurora cluster."
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
  description = "Aurora ${var.name} accepts traffic only from explicit client security groups."
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

resource "aws_rds_cluster_parameter_group" "this" {
  name        = var.name
  family      = "aurora-postgresql${split(".", var.engine_version)[0]}"
  description = "Cluster parameters for ${var.name}."

  dynamic "parameter" {
    for_each = var.cluster_parameters

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

resource "aws_rds_cluster" "this" {
  #checkov:skip=CKV_AWS_313:Serverless v2 scales the writer rather than adding readers; prod SEA runs writer-only and a reader is opt-in via reader_count.
  #checkov:skip=CKV_AWS_139:Deletion protection is var.deletion_protection, true by default. Dev sets it false so the environment can be destroyed.
  #checkov:skip=CKV2_AWS_8:Automated backups are configured through backup_retention_period. An AWS Backup plan is an estate-wide decision, not a per-cluster one.
  #checkov:skip=CKV2_AWS_27:Query logging needs pgaudit plus log_statement, which logs every statement including its arguments. Enable per cluster via var.cluster_parameters where the data warrants it.
  cluster_identifier = var.name
  engine             = "aurora-postgresql"
  engine_version     = var.engine_version
  engine_mode        = "provisioned" # required for Serverless v2
  database_name      = var.database_name
  port               = 5432

  master_username = var.master_username
  # RDS generates, stores and rotates the password, so no credential reaches
  # Terraform state.
  manage_master_user_password   = true
  master_user_secret_kms_key_id = aws_kms_key.this.arn

  db_subnet_group_name            = aws_db_subnet_group.this.name
  db_cluster_parameter_group_name = aws_rds_cluster_parameter_group.this.name
  vpc_security_group_ids          = [aws_security_group.this.id]

  storage_encrypted = true
  kms_key_id        = aws_kms_key.this.arn

  backup_retention_period      = var.backup_retention_days
  preferred_backup_window      = "17:00-18:00" # 01:00-02:00 SGT
  preferred_maintenance_window = "sun:18:00-sun:19:00"
  copy_tags_to_snapshot        = true

  deletion_protection       = var.deletion_protection
  skip_final_snapshot       = var.skip_final_snapshot
  final_snapshot_identifier = var.skip_final_snapshot ? null : "${var.name}-final"
  apply_immediately         = var.apply_immediately

  enabled_cloudwatch_logs_exports     = ["postgresql"]
  iam_database_authentication_enabled = true

  serverlessv2_scaling_configuration {
    min_capacity = var.min_capacity
    max_capacity = var.max_capacity
  }

  tags = {
    Name = var.name
  }

  depends_on = [aws_cloudwatch_log_group.postgresql]
}

# Stretches the interval of a rotation this module cannot turn off.
#
# RDS owns the master credential rotation schedule (seven days). No argument on
# aws_rds_cluster disables it, and CancelRotateSecret is refused because the
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
# cluster no longer accepts until the service is redeployed.
#
# No rotation_lambda_arn: it is optional in the provider schema and must be
# omitted for a managed secret, which RDS rotates without a function.
resource "aws_secretsmanager_secret_rotation" "master_password" {
  #checkov:skip=CKV_AWS_304:A caller that sets this variable is lengthening the interval, and the value it is likely to set -- 999, the AWS maximum -- is by definition more than 90 days. The check is right that this weakens rotation; that is the deliberate trade for a dev account whose tasks are stranded by every rotation. Prod leaves master_password_rotation_days null, creates none of this, and keeps RDS's seven days.
  count = var.master_password_rotation_days == null ? 0 : 1

  secret_id          = aws_rds_cluster.this.master_user_secret[0].secret_arn
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

resource "aws_rds_cluster_instance" "this" {
  #checkov:skip=CKV_AWS_353:Performance Insights is var.performance_insights_enabled, true by default. Dev turns it off; on a 0.5 ACU cluster it reports nothing useful.
  #checkov:skip=CKV_AWS_118:Enhanced monitoring is var.monitoring_interval, off by default. Per-second OS metrics on a 0.5 ACU dev cluster cost more than they reveal.
  count = 1 + var.reader_count

  identifier         = count.index == 0 ? "${var.name}-writer" : "${var.name}-reader-${count.index}"
  cluster_identifier = aws_rds_cluster.this.id
  instance_class     = "db.serverless"
  engine             = aws_rds_cluster.this.engine
  engine_version     = aws_rds_cluster.this.engine_version

  db_subnet_group_name = aws_db_subnet_group.this.name
  publicly_accessible  = false

  performance_insights_enabled    = var.performance_insights_enabled
  performance_insights_kms_key_id = var.performance_insights_enabled ? aws_kms_key.this.arn : null

  monitoring_interval = var.monitoring_interval
  monitoring_role_arn = var.monitoring_interval > 0 ? aws_iam_role.monitoring[0].arn : null

  auto_minor_version_upgrade = true
  apply_immediately          = var.apply_immediately
  copy_tags_to_snapshot      = true

  tags = {
    Name = count.index == 0 ? "${var.name}-writer" : "${var.name}-reader-${count.index}"
  }
}
