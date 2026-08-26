# workflow-bootstrap

One-shot Fargate task definition that runs Workflow schema bootstrap
(`setupDatabase`) against a service's Aurora. Not a long-running service:
nothing stays up until the application repository calls `ecs run-task`.

Shaped after prod Next's `impel-next-sea-workflow-bootstrap` one-shot, but
tag-resolved rather than digest-pinned so a dev pipeline can move `:bootstrap`
the same way it moves `:latest`.

Reuses the long-running service's execution role, task role and log group so
the task can pull the image, decrypt the RDS credentials secret, reach Aurora
and write logs without a second identity. The service's task security group
is not created here — the caller passes it at `run-task` time.

## Creates

- `aws_ecs_task_definition` — Fargate, `awsvpc`, X86_64, family from `family`
- `aws_iam_role_policy` on `deploy_role_name` — `ecs:RunTask` scoped to this
  family, conditioned on `cluster_arn`

`github-deploy-role` cannot express RunTask without a modules-repo change of
that module; the extra grant lives here instead.

## Call

```hcl
module "next_workflow_bootstrap" {
  source = "git::https://github.com/UseImpel/impel-terraform-modules.git//modules/workflow-bootstrap?ref=v1.2.0"

  family          = "impel-next-${var.environment}-workflow-bootstrap"
  container_image = "${local.ecr_registry}/impel-next/${var.image_repository_suffix}:bootstrap"

  execution_role_arn = module.service["next"].execution_role_arn
  task_role_arn      = module.service["next"].task_role_arn
  log_group_name     = module.service["next"].log_group_name

  environment_variables = {
    IMPEL_WORKFLOW_DATABASE_HOST = module.postgres["next"].endpoint
    IMPEL_WORKFLOW_DATABASE_NAME = module.postgres["next"].database_name
  }

  container_secrets = {
    IMPEL_WORKFLOW_DATABASE_CREDENTIALS_JSON = module.postgres["next"].master_user_secret_arn
  }

  deploy_role_name = module.service_deploy_role["next"].role_name
  cluster_arn      = module.ecs_cluster.cluster_arn
}
```

The application workflow then `run-task`s this family (network configuration
taken from the long-running service) and only afterwards
`update-service --force-new-deployment`.

## Notes

The image tag in `container_image` is MUTABLE in dev. Terraform registers the
family once; moving the tag is the deploy. An empty repository fails at
`run-task` pull time, same as a service whose `:latest` has not been pushed.
