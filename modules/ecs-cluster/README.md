# ecs-cluster

Fargate ECS cluster, shaped after the live `impel-gateway-sea` cluster documented in
[`docs/prod-sea-mapping.md`](../../docs/prod-sea-mapping.md).

## Creates

- `aws_ecs_cluster` with Container Insights
- `aws_ecs_cluster_capacity_providers` associating `FARGATE` and `FARGATE_SPOT`

Nothing else. Services are added by calling [`../ecs-service`](../ecs-service) once per workload
and passing this module's `cluster_arn`.

## Call

```hcl
module "ecs_cluster" {
  source = "../../modules/ecs-cluster"

  name = "impel-gateway-${var.environment}"
}
```

## Notes

Capacity provider association is a separate resource from the cluster because editing the provider
list on `aws_ecs_cluster` forces replacement — which would destroy every service running on it. The
split makes adding `FARGATE_SPOT` later an in-place update.

`default_capacity_provider_strategy` defaults to empty, matching prod, where each service declares
its own strategy rather than inheriting one.
