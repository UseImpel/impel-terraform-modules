# efs-volume

One EFS filesystem, encrypted at rest, with a security group and one access point per named
mount point. Built for a single Fargate task that needs a shared, persistent filesystem across
several containers — the meets data plane's postgres/minio/bridge volumes are the first caller.

## Creates

- `aws_efs_file_system` — encrypted, one per module call
- `aws_efs_mount_target` — one per entry in `subnet_ids`
- `aws_security_group` accepting `:2049` from `allowed_security_group_id` only
- `aws_efs_access_point` — one per entry in `access_points`, each pinning a POSIX uid/gid and
  creating its root directory with matching ownership if absent

## Call

```hcl
module "meets_data" {
  source = "../../modules/efs-volume"

  name                       = "impel-meets-${var.environment}-data"
  vpc_id                     = module.vpc.vpc_id
  subnet_ids                 = module.vpc.private_subnet_ids
  allowed_security_group_id  = module.meets_service.task_security_group_id

  access_points = {
    postgres-data = { root_directory_path = "/postgres-data", uid = 70, gid = 70, permissions = "0700" }
    minio-data    = { root_directory_path = "/minio-data", uid = 0, gid = 0, permissions = "0755" }
    bridge-data   = { root_directory_path = "/bridge-data", uid = 1000, gid = 1000, permissions = "0755" }
  }
}
```

Reference the outputs from a task definition's volume blocks:

```hcl
volume {
  name = "postgres-data"

  efs_volume_configuration {
    file_system_id     = module.meets_data.file_system_id
    transit_encryption = "ENABLED"

    authorization_config {
      access_point_id = module.meets_data.access_point_ids["postgres-data"]
      iam             = "DISABLED"
    }
  }
}
```

Transit encryption and IAM authorization are mount-time settings on the task definition's volume
block, not on the filesystem — this module has no toggle for either. Pass them at the call site
above, matching prod: transit encryption on, IAM auth off.

## The security group direction

Same idiom as `ecs-service`'s `data_store_ingress`: the ingress rule lives on **this module's own**
security group, referencing the caller's task security group — not the other way around. Building
the filesystem first with no clients, then letting the service grant itself access, keeps the
dependency graph acyclic. There is deliberately only one `allowed_security_group_id`, not a list —
one Fargate task mounts this volume; a second client is a sign the filesystem should not be shared.

## Access point ownership

Each access point's `posix_user` and `root_directory.creation_info` use the same uid/gid, so a
container mounting through the access point sees itself as that owner regardless of the IAM
principal ECS assumed. If the root directory does not already exist, EFS creates it on first mount
with the given owner and `permissions`. An access point does not change the uid/gid a process runs
as inside the container — that still comes from the image or task definition — it changes what the
filesystem believes that uid/gid owns.

## Dev is disposable

There is no `kms_key_arn` requirement and no lifecycle protection on the filesystem: destroying the
module destroys the data with it. That matches the account's force-delete doctrine for dev; a prod
caller should pass a dedicated CMK via `kms_key_arn`.
