# modules

Reusable blueprints. Every module here is called by two or more accounts, or is
on its way to being.

Modules are written when a real workload needs one — a `vpc/` directory
containing a guess at what a VPC should look like is worse than no directory at
all, because the guess gets copied. Everything here was written against the live
prod SEA topology recorded in
[`../docs/prod-sea-mapping.md`](../docs/prod-sea-mapping.md).

| | |
|---|---|
| [`vpc`](vpc/) | VPC, public and private subnets, NAT, interface and gateway endpoints |
| [`ecs-cluster`](ecs-cluster/) | Fargate cluster with Container Insights |
| [`ecs-service`](ecs-service/) | Task definition, service, target group, listener rule, autoscaling, IAM |
| [`alb`](alb/) | Load balancer, listeners, optional access logs. No WAF — that stays a caller decision |
| [`acm-certificate`](acm-certificate/) | DNS-validated certificate. Publishes the validation records; does not create them |
| [`aurora-serverless`](aurora-serverless/) | Aurora PostgreSQL Serverless v2 with RDS-managed credentials |
| [`valkey`](valkey/) | ElastiCache Valkey replication group, TLS and auth token |
| [`memorydb`](memorydb/) | MemoryDB Redis cluster, TLS and ACL user (Next cache) |
| [`ecr-repo`](ecr-repo/) | Repository, lifecycle policy, optional cross-account pull |
| [`service-secret`](service-secret/) | Secrets Manager secret whose shape Terraform owns and whose values it does not |
| [`app-bucket`](app-bucket/) | Private SSE-KMS bucket, lifecycle expiry, and a managed policy for object access |

## The contract

A module is reusable only if it is ignorant of where it runs.

- **No hardcoded environment values.** No account IDs, no CIDR blocks, no
  `dev`/`prod` strings, no ARNs. Anything that differs between accounts is a
  variable. The account stack supplies it.
- **No `provider` blocks, no `backend` blocks.** Both belong to the root module.
  A module that configures its own provider cannot be called twice.
- **No `terraform.tfvars`.** Values come from the caller.
- **Typed variables**, each with a `description` and, where a wrong value is
  possible, a `validation` block. Fail at plan time, not at apply time.
- **Outputs for everything the caller could need.** A caller that has to reach
  into a module's internals means an output is missing.
- **`versions.tf`** declaring `required_providers` and a `required_version`
  floor. The floor states what the module's own syntax needs — `precondition`
  blocks, `optional()` type defaults — and is deliberately a `>=` range, not a
  pin: how far forward to track stays the root module's decision. `.tflint.hcl`
  enables `terraform_required_version`, so a module without one fails CI.
- **`README.md`** stating what the module creates and showing one call.

## Layout

```
modules/<name>/
├── main.tf
├── variables.tf
├── outputs.tf
├── versions.tf
└── README.md
```

Flat, named for what it builds: `vpc`, `ecs-cluster`, `database`. No `aws/`
prefix — this estate is AWS-only, and the day it is not, a sibling directory is
a smaller change than a rename of everything.

## Calling one

From `accounts/<env>/main.tf`, by relative path. No registry, no versioning:
the module and its callers are in one repo, so a change to a module is planned
against every account that uses it in the same pull request.

```hcl
module "vpc" {
  source = "../../modules/vpc"

  environment = var.environment
  cidr_block  = "10.10.0.0/16"
}
```

A change under `modules/` triggers **every** environment's plan pipeline —
`modules/**` is in the path filter of each `plan-<env>.yml` — so the blast
radius is visible in the PR before anyone approves it.
