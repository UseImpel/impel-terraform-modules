# Modules

Reusable AWS blueprints. Each module is provider-agnostic and receives all
account, environment, network, and sizing values from its caller.

| Area | Modules |
|---|---|
| Network | [`vpc`](vpc/), [`alb`](alb/), [`acm-certificate`](acm-certificate/), [`private-dns-namespace`](private-dns-namespace/) |
| Compute | [`ecs-cluster`](ecs-cluster/), [`ecs-service`](ecs-service/), [`meets-service`](meets-service/), [`engine-tasks`](engine-tasks/), [`workflow-bootstrap`](workflow-bootstrap/), [`ssm-bastion`](ssm-bastion/) |
| Data/storage | [`aurora-serverless`](aurora-serverless/), [`valkey`](valkey/), [`memorydb`](memorydb/), [`efs-volume`](efs-volume/), [`ecr-repo`](ecr-repo/), [`service-secret`](service-secret/), [`app-bucket`](app-bucket/), [`artifacts-bucket`](artifacts-bucket/), [`sessions-payload-bucket`](sessions-payload-bucket/), [`inbound-events`](inbound-events/), [`work-queue`](work-queue/) |
| Identity | [`github-deploy-role`](github-deploy-role/) |

Use immutable release tags when calling modules. See the repository README for
release and validation conventions.
