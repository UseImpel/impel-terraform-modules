# aurora-serverless

Aurora PostgreSQL Serverless v2 cluster, shaped after the four clusters in prod SEA documented in
[`docs/prod-sea-mapping.md`](../../docs/prod-sea-mapping.md): one `db.serverless` writer, a
per-cluster CMK, `postgresql` log export, Performance Insights, credentials in Secrets Manager.

## Creates

- `aws_rds_cluster` (`engine_mode = "provisioned"` with a Serverless v2 scaling block — that is how
  SLSv2 is expressed) plus one writer and optional readers
- KMS CMK and alias `alias/<name>-database`, encrypting storage, the credentials secret and
  Performance Insights
- DB subnet group, cluster parameter group
- Security group accepting `:5432` from `allowed_security_group_ids`
- CloudWatch log group for the exported `postgresql` logs
- Enhanced monitoring IAM role, when `monitoring_interval > 0`

## Call

```hcl
module "gateway_db" {
  source = "../../modules/aurora-serverless"

  name                       = "impel-gateway-${var.environment}-postgres"
  vpc_id                     = module.vpc.vpc_id
  subnet_ids                 = module.vpc.private_subnet_ids
  allowed_security_group_ids = [module.gateway_service.task_security_group_id]

  min_capacity          = 0.5
  max_capacity          = 2
  backup_retention_days = 1
  deletion_protection   = false
  skip_final_snapshot   = true
}
```

## The password

`manage_master_user_password = true`. RDS generates the password, stores it in a Secrets Manager
secret encrypted with this module's CMK, and rotates it. **No credential passes through Terraform
state**, and there is no `random_password` resource to leak one.

Inject it into a task definition through `master_user_secret_arn`:

```hcl
container_secrets = {
  PG_PASSWORD = "${module.gateway_db.master_user_secret_arn}:password::"
  PG_HOST     = "..." # from module.gateway_db.endpoint, via environment not secrets
}
```

The secret's JSON holds `username` and `password`.

## Notes

Ingress is by **source security group only** — there is no CIDR variable. Two prod clusters
(`impel-gateway-sea-database`, `impel-gateway-sea-redis`) still allow the whole `10.90.0.0/16`
range; that is the one prod behaviour this module deliberately does not reproduce.

`allowed_security_group_ids` is fine when nothing flows back from the cluster to the client. When a
service also consumes an output of this module — `kms_key_arn` for its execution role, or
`endpoint` for its configuration — that direction creates a dependency cycle. In that case leave
`allowed_security_group_ids` empty and grant access from the service side with the `ecs-service`
module's `data_store_ingress`.

The `postgresql` log group is created by Terraform before the cluster so it carries
`log_retention_days`. Left to RDS, it is created on first write with retention set to never expire.

`engine_mode` is `"provisioned"`, not `"serverless"`. Serverless **v1** used the latter; v2 is a
provisioned cluster with `serverlessv2_scaling_configuration` and `db.serverless` instances.

Defaults lean production-safe: `deletion_protection = true`, `skip_final_snapshot = false`. Dev must
set both the other way or `terraform destroy` will not complete.
