# ecs-service

One Fargate service, end to end. The workhorse module — every default is taken from the live prod
SEA services documented in [`docs/prod-sea-mapping.md`](../../docs/prod-sea-mapping.md).

## Creates

- CloudWatch log group `/ecs/<name>/service`
- Two IAM roles — execution (pull image, read secrets) and task (runtime identity)
- Task security group, accepting the container port **from the load balancer only**
- Task definition (Fargate, `awsvpc`, X86_64/Linux)
- Target group (`target_type = "ip"`) and a listener rule, when `attach_load_balancer` is true
- ECS service with circuit breaker + rollback, `100/200` deployment percentages, AZ rebalancing
- `aws_appautoscaling_target` plus up to three target-tracking policies (CPU, memory, ALB requests)

## Call

```hcl
module "gateway_service" {
  source = "../../modules/ecs-service"

  name        = "impel-gateway-${var.environment}"
  cluster_arn = module.ecs_cluster.cluster_arn
  vpc_id      = module.vpc.vpc_id
  subnet_ids  = module.vpc.private_subnet_ids

  container_name  = "gateway"
  container_image = "${module.ecr_gateway.repository_url}@sha256:${var.gateway_image_digest}"
  container_port  = 8080
  cpu             = 512
  memory          = 1024

  environment_variables = { PORT = "8080" }
  container_secrets     = module.gateway_runtime_secret.container_secrets

  listener_arn                    = module.alb.listener_arn
  load_balancer_security_group_id = module.alb.security_group_id
  load_balancer_arn_suffix        = module.alb.arn_suffix
  listener_rule_priority          = 100
  listener_rule_host_headers      = ["gateway.dev.example.com"]
  health_check_path               = "/health"

  autoscaling_min_capacity = 1
  autoscaling_max_capacity = 2
  requests_per_target      = 200
}
```

## Reaching data stores

Pass the store's security group and port; this module writes the ingress rule onto **the store's**
security group:

```hcl
data_store_ingress = {
  postgres = { security_group_id = module.gateway_db.security_group_id, port = 5432 }
  cache    = { security_group_id = module.gateway_cache.security_group_id, port = 6379 }
}
```

The direction is deliberate. Having the database take a list of client security groups reads more
naturally, but it makes the database depend on the service — and a service that also needs the
database's KMS key or endpoint then depends back on the database. Terraform refuses to plan the
cycle. Building the store first with no clients, then letting each service grant itself access,
keeps the graph acyclic.

The data modules still expose `allowed_security_group_ids` for the simple case where nothing flows
back the other way.

## Service discovery and peer ingress

Both default to off; a caller that sets neither gets exactly the resources it got before.

A service with no load balancer is unreachable twice over: nothing resolves to it and its security
group accepts nothing. `service_registry_arn` fixes the first — pass an entry from the
[`private-dns-namespace`](../private-dns-namespace) module's `service_registry_arns` and ECS
registers each task's address under the namespace. `ingress_security_group_rules` fixes the second,
writing ingress onto **this service's own** task security group for each named peer:

```hcl
module "query_service" {
  # ...
  attach_load_balancer = false
  service_registry_arn = module.code_intelligence_dns.service_registry_arns["query"]

  ingress_security_group_rules = {
    api = { security_group_id = module.api_service.task_security_group_id, port = 7700 }
  }
}
```

Note the direction relative to `data_store_ingress`: data-store rules land on the store's group
(the service grants itself access), peer rules land on this service's group (the callee declares
who may call it). Both keep the graph acyclic as long as calls flow one way; two services that call
each other need one side to pass a literal security group ID instead.

## Two roles, not one

The **execution role** is what the ECS agent uses before the container starts: pull the image, read
the secrets. The **task role** is what application code assumes at runtime. Merging them would hand
the application permission to read every secret the task definition names — including ones it was
never meant to see.

Secret access on the execution role is scoped to exactly the ARNs in `container_secrets`. Adding a
secret to that map is what grants access to it; nothing broader is implied. Secrets encrypted with
a CMK also need that key in `secret_kms_key_arns`, or the task fails to start with an
`AccessDeniedException` on `kms:Decrypt`.

## Autoscaling owns the task count

`desired_count` applies at creation only — `ignore_changes = [desired_count]` on the service means a
later apply will not reset a scaled-out service. To change the running count deliberately, adjust
`autoscaling_min_capacity`.

The `ALBRequestCountPerTarget` policy needs `load_balancer_arn_suffix`. The resource label is a
positional string (`<lb-suffix>/<tg-suffix>`) that is not validated at apply time: get it wrong and
the policy creates cleanly, then never fires. A `precondition` catches the missing input at plan
time.

## Sidecars

The task may include optional sidecars. They use the same task network
namespace, so loopback adapters can be exposed to the primary container
without opening additional security-group ingress:

```hcl
sidecars = {
  redis = {
    container_name       = "redis-rest-adapter"
    container_image      = var.container_image
    container_port       = 8081
    command              = ["/app/redis-rest-adapter"]
    health_check_command = ["CMD", "/app/redis-rest-adapter", "healthcheck"]
  }
}

container_dependencies = [
  { container_name = "redis-rest-adapter", condition = "HEALTHY" },
]
```

Sidecar secrets are included in the execution-role permissions automatically.
Use `container_stop_timeout` and each sidecar's `stop_timeout` for workloads
that need a bounded graceful shutdown.

## Who deploys new images

Two postures, chosen with `continuous_deployment`.

**Default (`false`) — this repository is authoritative.** The service runs exactly the digest in
`container_image`. Shipping a new build means a PR here, reviewed, planned and applied. Use this
when the deploy decision belongs with infrastructure review.

**`true` — the application repository rolls its own images.** Terraform still renders the task
definition and creates the service with the digest it knows, but it stops reconciling *which
revision the service runs*. The application's merge pipeline pushes to ECR and calls
`aws ecs update-service`, and that revision survives the next apply.

Without the flag the two halves fight: the app pipeline moves the service forward and the next
`terraform apply` — triggered by something else entirely — quietly rolls it back to the digest
recorded here. The failure is confusing precisely because the apply that reverts the deploy is
usually unrelated to it.

```hcl
module "identity_service" {
  # ...
  continuous_deployment = true
}
```

The service's deploy role still needs `ecs:UpdateService` and `ecs:DescribeServices` on it, plus
`iam:PassRole` for the task and execution roles. That role is not managed by this module.

Implementation note: `ignore_changes` takes a static list and cannot be built from a variable, so
the flag selects between two `aws_ecs_service` resources with `count`. Their argument bodies are
identical and must stay that way — only the `lifecycle` block differs. Everything downstream reads
`local.service`, so both module outputs work either way.

## Load balancer attachment

`attach_load_balancer` (default `true`) is what turns the load balancer path on. It drives `count`
on the target group, listener rule and task ingress rule, so it **must be a literal the caller
sets** — `listener_arn` is unknown until the ALB exists, and deriving `count` from it fails at plan
with *"The count value depends on resource attributes that cannot be determined until apply."*

With it on, `listener_arn`, `load_balancer_security_group_id` and `listener_rule_priority` are all
required, plus at least one of `listener_rule_host_headers` / `listener_rule_path_patterns`. Each is
checked by a `precondition` so a misconfiguration fails at plan rather than producing a service
whose targets never pass a health check.

Set `attach_load_balancer = false` for a worker with no inbound traffic; the target group, listener
rule, ingress rule and request-count policy are all skipped.

Priorities must be unique per listener. With a shared ALB, allocate them in the account stack — the
convention in `accounts/dev` is one hundred per service.
