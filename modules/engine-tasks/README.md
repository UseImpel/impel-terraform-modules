# engine-tasks

One-off Fargate task definitions for the code-intelligence engine fleet
(checkout, toolbox, zoekt, gitnexus, scip-typescript, opengrep, ...), the
security groups those tasks run behind, and the RunTask policies the worker
and query services need to launch them. Nothing here is a service: the fleet
is started ad hoc via `ecs:RunTask` and each task terminates when its job
ends.

Terraform port of the engine fleet in code-intelligence
`infra/aws/lib/runtime-stack.ts` — the `engineTask()` helper, the
engine/checkout security groups, and the RunTask grants on the query and
worker task roles.

## Creates

- `aws_ecs_task_definition` per `tasks` entry — Fargate, `awsvpc`, X86_64,
  family `<name_prefix>-engine-<key>`, per-entry cpu/memory/ephemeral
  storage/entrypoint, `nofile` 65536, `stopTimeout` 120
- `aws_cloudwatch_log_group` — one shared group, stream prefix per engine
- `aws_iam_role` x2 — shared fleet execution role (ECR pull + logs) and a
  shared **credential-free** task role with no policies
- `aws_security_group` "checkout" — open egress, no ingress
- `aws_security_group` "engine" — sealed: egress only to VPC DNS (53), the
  shared interface endpoints (443) and the S3 gateway prefix list (443); no
  ingress
- `aws_iam_policy` x2 — worker (all families, ExecutionKind checkout/index)
  and query (non-checkout families, ExecutionKind query) RunTask grants,
  attached by the caller via ecs-service `task_role_policy_arns`

## Security model

The fleet task role deliberately carries **no data-store permissions** —
no S3, no KMS, no Secrets Manager. Sealed engine tasks are credential-free:
all artifact I/O uses short-lived prefix-scoped presigned URLs minted by the
services and delivered in the job input payload. Checkout credentials arrive
the same way — there is no secret wiring in these task definitions, by
design. Do not attach policies to the task role to "fix" an engine's access;
that breaks the seal.

The two security groups are the two network postures:

- **checkout** clones from customer repository hosts whose addresses are not
  enumerable, so its egress is open (matching the CDK's
  `allowAllOutbound: true`). It has no ingress and the task terminates before
  indexing begins.
- **engine** never sees the internet. DNS to the VPC resolver, TLS to the
  ECR/CloudWatch interface endpoints, TLS to the S3 gateway endpoint —
  nothing else, no ingress.

Every RunTask launch must carry `Application` and `ExecutionKind` request
tags (and may carry `Tenant`/`Engine`); the Describe/Stop grant is scoped by
those same tags, so worker and query can each manage only the kinds of task
they launch.

## Call

```hcl
module "engine_tasks" {
  source = "git::https://github.com/UseImpel/impel-terraform-modules.git//modules/engine-tasks?ref=v1.3.0"

  name_prefix = "impel-code-intelligence-dev"

  tasks = {
    checkout = { image = local.toolbox_image, cpu = 2048, memory = 4096, ephemeral_gib = 100, entrypoint = ["aws-engine"] }
    toolbox  = { image = local.toolbox_image, cpu = 4096, memory = 8192, ephemeral_gib = 100, entrypoint = ["aws-engine"] }
    zoekt    = { image = local.zoekt_image, cpu = 4096, memory = 8192, ephemeral_gib = 100, entrypoint = ["aws-engine"] }
    gitnexus = { image = local.gitnexus_image, cpu = 8192, memory = 16384, ephemeral_gib = 100, entrypoint = ["aws-engine"] }
  }

  vpc_id                     = module.vpc.vpc_id
  vpc_dns_cidr               = "${cidrhost(module.vpc.vpc_cidr, 2)}/32"
  endpoint_security_group_id = module.vpc.endpoint_security_group_id
  s3_prefix_list_id          = module.vpc.s3_prefix_list_id
  cluster_arn                = module.ecs_cluster.cluster_arn
}
```

The worker/query services then get:

```hcl
task_role_policy_arns = [module.engine_tasks.worker_runtask_policy_arn]

environment_variables = {
  CODE_INTELLIGENCE_AWS_TASK_DEFINITIONS_JSON = jsonencode(merge(
    module.engine_tasks.task_definition_arns,
    { "ast-grep" = module.engine_tasks.task_definition_arns["toolbox"] },
  ))
  CODE_INTELLIGENCE_AWS_ECS_SECURITY_GROUP_IDS      = module.engine_tasks.engine_security_group_id
  CODE_INTELLIGENCE_AWS_CHECKOUT_SECURITY_GROUP_IDS = module.engine_tasks.checkout_security_group_id
}
```

## Notes

- Network configuration (subnets + security group) is supplied at run-task
  time by the calling service, not registered here — the same task definition
  launches behind the checkout or the engine group depending on
  `ExecutionKind`.
- The key `"checkout"` in `tasks` is load-bearing: that family is granted to
  the worker policy only and excluded from query's.
- The RunTask policies grant per-family `task-definition/<family>:*` ARNs, so
  re-registering a revision does not invalidate them; the CDK equivalent
  grants the revision-pinned ARNs it just deployed.
