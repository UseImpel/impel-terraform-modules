# Modules

Reusable AWS blueprints. Each module is provider-agnostic and receives all
account, environment, network, and sizing values from its caller.

| Area | Modules |
|---|---|
| Network | [`vpc`](vpc/), [`alb`](alb/), [`acm-certificate`](acm-certificate/), [`private-dns-namespace`](private-dns-namespace/) |
| Compute | [`ecs-cluster`](ecs-cluster/), [`ecs-service`](ecs-service/), [`meets-service`](meets-service/), [`ssm-bastion`](ssm-bastion/) |
| Data/storage | [`aurora-serverless`](aurora-serverless/), [`rds-postgres`](rds-postgres/), [`valkey`](valkey/), [`efs-volume`](efs-volume/), [`ecr-repo`](ecr-repo/), [`service-secret`](service-secret/), [`app-bucket`](app-bucket/), [`sessions-payload-bucket`](sessions-payload-bucket/), [`inbound-events`](inbound-events/) |
| Edge delivery | [`cloudfront-spa-api`](cloudfront-spa-api/) |
| Identity | [`github-deploy-role`](github-deploy-role/), [`github-static-site-deploy-role`](github-static-site-deploy-role/) |

Use immutable release tags when calling modules. See the repository README for
release and validation conventions.
