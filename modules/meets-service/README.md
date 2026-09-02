# meets-service

One Fargate service running a fixed set of interdependent containers that share EFS-backed
volumes — the meets data plane. Not `ecs-service` with a flag: that module's defaults (rolling
`100/200` deploys, AZ rebalancing enabled, always-on autoscaling) assume stateless, horizontally
scalable replicas. This task holds the sole writer to its own postgres and minio volumes, so a
second task starting before the first stops would fight it for those mounts. This module pins
`desired_count = 1`, deploys stop-then-start, and has no autoscaling at all.

## Creates

- CloudWatch log group `/ecs/<name>/service`, one stream per container name
- Two IAM roles — execution (pull images, read secrets) and task (runtime identity every
  container shares)
- Task security group, accepting the primary container's port **from the load balancer only**
- Task definition (Fargate, `awsvpc`, X86_64/Linux) with one container per entry in `containers`,
  and a `volume` block per entry in `volumes`
- Target group (`target_type = "ip"`) and a listener rule, when `attach_load_balancer` is true
- ECS service with circuit breaker + rollback, `100/0` deployment percentages, AZ rebalancing
  disabled, `desired_count = 1`

## Call

```hcl
module "meets_service" {
  source = "../../modules/meets-service"

  name        = "impel-meets-${var.environment}"
  cluster_arn = module.ecs_cluster.cluster_arn
  vpc_id      = module.vpc.vpc_id
  subnet_ids  = module.vpc.private_subnet_ids

  cpu    = 2048
  memory = 4096

  primary_container_name = "gateway"

  containers = {
    postgres = {
      image  = "postgres:16"
      cpu    = 256
      memory = 512
      environment_variables = { POSTGRES_PASSWORD_FILE = "/run/secrets/postgres-password" }
      health_check_command  = ["CMD-SHELL", "pg_isready -U postgres"]
      stop_timeout          = 60
      mount_points = [
        { volume_name = "postgres-data", container_path = "/var/lib/postgresql/data" },
      ]
    }

    gateway = {
      image = "${module.ecr_gateway.repository_url}@sha256:${var.gateway_image_digest}"
      cpu   = 256
      memory = 384
      port  = 8080
      depends_on = [
        { container_name = "admin-api", condition = "HEALTHY" },
        { container_name = "meeting-api", condition = "HEALTHY" },
        { container_name = "valkey", condition = "START" },
      ]
    }

    # ... the remaining eight containers, each with its own cpu/memory/depends_on.
  }

  volumes = {
    postgres-data = {
      file_system_id  = module.meets_data.file_system_id
      access_point_id = module.meets_data.access_point_ids["postgres-data"]
    }
  }

  listener_arn                    = module.alb.listener_arn
  load_balancer_security_group_id = module.alb.security_group_id
  listener_rule_priority          = 100
  listener_rule_host_headers      = ["meets.dev.example.com"]
  health_check_path               = "/health"
}
```

`meets_service.task_security_group_id` is the input `efs-volume` expects for
`allowed_security_group_id` — see that module's README for the other half of this wiring.

## Every container is essential

Unlike `ecs-service`'s single primary container plus optional sidecars, there is no
primary/sidecar distinction here: `containers` is a flat map and every entry is `essential = true`
in the rendered task definition. The meets data plane is ten containers wired together with
`depends_on` (postgres/valkey/minio have none; the API containers wait on their stores; gateway
waits on the APIs; mcp/pocket-ingest/terminal wait on gateway) — losing any one of them is a
partial outage, not a degraded sidecar, so there is nothing to optionally omit.

`primary_container_name` names the one container the load balancer forwards to; every other
container is reached over `localhost` inside the shared task network namespace, not through the
task security group.

## Two roles, not one

Same split as `ecs-service`: the **execution role** pulls images and reads secrets before any
container starts; the **task role** is what every container's application code assumes at
runtime, shared across all ten rather than scoped per-container — Fargate has one task role per
task definition, not one per container. Secret access on the execution role is scoped to exactly
the ARNs named across every container's `secrets` map.

## Why not autoscaling, why not rolling deploys

KTD2's constraint, not an oversight. Postgres and minio here are containers holding the sole
write handle to their own EFS access points — nothing else may open them concurrently. That rules
out two things `ecs-service` takes for granted:

- **Autoscaling.** A second task would mean a second writer. There is no
  `autoscaling_min_capacity`/`max_capacity` here at all; `desired_count` is the literal `1`,
  hardcoded, not a variable.
- **Rolling deploys.** `ecs-service`'s default `100/200` briefly runs the old and new task
  together. This module hardcodes `deployment_maximum_percent = 100` and
  `deployment_minimum_healthy_percent = 0` instead: the running task is stopped, then the new one
  starts. `availability_zone_rebalancing` is `"DISABLED"` for the same reason — AWS rejects
  `"ENABLED"` outright whenever `maximum_percent <= 100`.

The tradeoff is downtime on every deploy, for as long as the dependency chain takes to become
healthy again — hence `health_check_grace_period` defaulting to 900 seconds rather than
`ecs-service`'s 180.

## Sizing containers, not just the task

`cpu` and `memory` are the task-level totals and are required with no default — unlike
`ecs-service`, where a single container makes 512/1024 a reasonable guess, a ten-container task
needs a deliberate number. Every container's own `cpu`/`memory` are soft reservations; the task
definition has a `precondition` rejecting a plan where they sum past the task total.

## Who deploys new images

Same `continuous_deployment` posture as `ecs-service` — `false` (default) makes this repository
authoritative for every container's image digest; `true` lets the application repository's deploy
pipeline advance the running task definition without a later `terraform apply` reverting it. See
`ecs-service`'s README for the full rationale; it applies unchanged here.

## Load balancer attachment

Same mechanics as `ecs-service`: `attach_load_balancer` must be a literal the caller sets (it
drives `count` on the target group, listener rule, and load-balancer ingress rule), and turning it
on requires `listener_arn`, `load_balancer_security_group_id`, `listener_rule_priority`, and at
least one of `listener_rule_host_headers` / `listener_rule_path_patterns` — each checked by a
`precondition` at plan time.
