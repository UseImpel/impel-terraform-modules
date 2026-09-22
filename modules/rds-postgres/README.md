# rds-postgres

Provisioned RDS for PostgreSQL: one single-AZ instance on gp3.

The interface deliberately mirrors [`aurora-serverless`](../aurora-serverless) so a caller can stand
this up beside a cluster and cut over by changing which module's outputs it reads. Read
[Replacing an Aurora cluster](#replacing-an-aurora-cluster) before doing that — there is one output
that is **not** interchangeable.

## Creates

- `aws_db_instance` (`engine = "postgres"`, `storage_type = "gp3"`, single-AZ unless `multi_az`)
- KMS CMK and alias `alias/<name>-database`, encrypting storage, the credentials secret and
  Performance Insights
- DB subnet group, instance parameter group (family `postgres<major>`)
- Security group accepting `:5432` from `allowed_security_group_ids`
- CloudWatch log group for the exported `postgresql` logs
- Enhanced monitoring IAM role, when `monitoring_interval > 0`

## Call

```hcl
module "gateway_db" {
  source = "../../modules/rds-postgres"

  name                       = "impel-gateway-${var.environment}-postgres-rds"
  vpc_id                     = module.vpc.vpc_id
  subnet_ids                 = module.vpc.private_subnet_ids
  allowed_security_group_ids = [module.gateway_service.task_security_group_id]

  instance_class        = "db.t4g.small"
  backup_retention_days = 1
  deletion_protection   = false
  skip_final_snapshot   = true
}
```

## Why this instead of Serverless v2

Aurora Serverless v2 bills its **floor** around the clock. At a 0.5 ACU minimum that is
0.5 × 730 h × $0.20 = **$73/month per cluster in ap-southeast-1**, whether or not anything connects.
A `db.t4g.micro` is the same 1 GiB of memory for $18.25/month, and `db.t4g.small` — 2 GiB, more than
the floor gives — is $37.23.

`min_capacity = 0` (auto-pause) closes that gap, but only for a cluster that reaches **zero client
connections** for the full idle window. A service holding a pooled connection around the clock never
pauses and keeps paying the floor. Auto-pause is the better answer for a genuinely idle database;
this module is the better answer for one that is small but never quiet.

Storage differs too. Aurora bills `StorageIOUsage` per request; gp3 does not bill per I/O at all,
and 20 GiB — the gp3 minimum — includes 3000 IOPS and 125 MiB/s.

What you give up: no Serverless scaling, no reader endpoint, no cluster-level failover. `multi_az`
buys a standby, at double the instance charge.

## Sizing

`instance_class` defaults to `db.t4g.micro` (1 GiB), which matches the 0.5 ACU Aurora floor it
replaces. Use `db.t4g.small` (2 GiB) where the database holds pooled connections around the clock.

`allocated_storage` defaults to 20 GiB because that is the gp3 minimum, not because anything needs
20 GiB — there is nothing to save by asking for less. `max_allocated_storage` defaults to 100, so a
volume that does start filling autoscales rather than taking the database down. Set it to `0` to
turn autoscaling off.

Backup storage up to the allocated size is free, so `backup_retention_days = 1` costs nothing.

## The password

`manage_master_user_password = true`, exactly as in `aurora-serverless`. RDS generates the password,
stores it in a Secrets Manager secret encrypted with this module's CMK, and rotates it. **No
credential passes through Terraform state.**

Inject it into a task definition through `master_user_secret_arn`:

```hcl
container_secrets = {
  PG_PASSWORD = "${module.gateway_db.master_user_secret_arn}:password::"
}
```

The secret's JSON holds `username` and `password`.

### Rotation

RDS turns on **managed rotation** at **seven days** and owns the schedule. It cannot be turned off:
the secret's `OwningService` is `rds`, so `CancelRotateSecret` is refused and no Terraform argument
exists to disable it.

`master_password_rotation_days` sets the interval, and **999 days is the Secrets Manager maximum** —
which is how a dev account opts out in practice. Leave it `null` to keep RDS's seven days. Prod
should.

**Rotation strands running tasks.** ECS resolves a task definition's `secrets` block only when a task
*starts*, so after a rotation every running task keeps the old credential until something redeploys
the service. `rotate_immediately` is `false` here on purpose — the provider defaults it to `true`,
which would rotate the password the moment the change applies.

Because `CancelRotateSecret` is also this resource's destroy path, the schedule resource is created
only when the variable is non-null. Setting it and later returning it to `null` produces a destroy
that fails; change the number instead.

## Replacing an Aurora cluster

**`endpoint` is the trap.** `aws_db_instance` exposes two attributes: `address` is the bare hostname,
`endpoint` is `host:port`. `aws_rds_cluster.endpoint` is the bare hostname. This module's `endpoint`
output is therefore wired to `.address`, so it drops straight into a caller that already appends the
port itself. Use `endpoint_with_port` only if you actually want one combined string.

Everything else lines up: `master_user_secret_arn`, `kms_key_arn`, `security_group_id`, `port`,
`database_name` and `master_username` have the same shape and meaning as in `aurora-serverless`.

Two things do not carry over:

- **There is no in-place conversion.** Aurora and RDS are different resources; `aws rds
  create-blue-green-deployment` works within an engine family, not across. Moving data means
  `pg_dump`/`pg_restore` (or DMS for a database large enough to justify it).
- **Parameter groups are per-family.** This module builds a `postgres<major>` group, so
  Aurora-only parameters — `rds.logical_replication` among them — do not exist here. Pass
  `instance_parameters`, not the Aurora module's `cluster_parameters`.

## Notes

Ingress is by **source security group only** — there is no CIDR variable.

`allowed_security_group_ids` is fine when nothing flows back from the instance to the client. When a
service also consumes an output of this module — `kms_key_arn` for its execution role, or `endpoint`
for its configuration — that direction creates a dependency cycle. In that case leave
`allowed_security_group_ids` empty and grant access from the service side with the `ecs-service`
module's `data_store_ingress`.

The `postgresql` log group is created by Terraform before the instance so it carries
`log_retention_days`. Left to RDS, it is created on first write with retention set to never expire.

`auto_minor_version_upgrade` is **false**, unlike the Aurora module. `engine_version` here is a full
`major.minor` string, so RDS taking a minor upgrade on its own would show as permanent drift on the
next plan. Bump `engine_version` to take a minor.

`subnet_ids` still needs two AZs even single-AZ: RDS requires the subnet group to span two.

Defaults lean production-safe: `deletion_protection = true`, `skip_final_snapshot = false`. Dev must
set both the other way or `terraform destroy` will not complete.
