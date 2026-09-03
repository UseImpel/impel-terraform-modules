# modules

Reusable blueprints. Every module here is called by two or more accounts, or is
on its way to being.

Modules are written when a real workload needs one — a `vpc/` directory
containing a guess at what a VPC should look like is worse than no directory at
all, because the guess gets copied. Everything here was written against the live
prod SEA topology recorded in [`docs/prod-sea-mapping.md`][mapping] in the prod
live repository.

[mapping]: https://github.com/UseImpel/impel-infra-prod/blob/main/docs/prod-sea-mapping.md

| | |
|---|---|
| [`vpc`](vpc/) | VPC, public and private subnets, NAT, interface and gateway endpoints |
| [`ecs-cluster`](ecs-cluster/) | Fargate cluster with Container Insights |
| [`ecs-service`](ecs-service/) | Task definition, service, target group, listener rule, autoscaling, IAM |
| [`meets-service`](meets-service/) | One Fargate service of interdependent containers sharing EFS volumes. Single writer, no autoscaling — not `ecs-service` with a flag |
| [`engine-tasks`](engine-tasks/) | One-off Fargate task definitions for the code-intelligence engine fleet, started via `RunTask` |
| [`alb`](alb/) | Load balancer, listeners, optional access logs. No WAF — that stays a caller decision |
| [`acm-certificate`](acm-certificate/) | DNS-validated certificate. Publishes the validation records; does not create them |
| [`private-dns-namespace`](private-dns-namespace/) | Private Cloud Map namespace and A-record discovery services — stable in-VPC names with no load balancer |
| [`aurora-serverless`](aurora-serverless/) | Aurora PostgreSQL Serverless v2 with RDS-managed credentials |
| [`valkey`](valkey/) | ElastiCache Valkey replication group, TLS and auth token |
| [`memorydb`](memorydb/) | MemoryDB Redis cluster, TLS and ACL user (Next cache) |
| [`efs-volume`](efs-volume/) | Encrypted EFS filesystem with one access point per named mount point |
| [`ecr-repo`](ecr-repo/) | Repository, lifecycle policy, optional cross-account pull |
| [`github-deploy-role`](github-deploy-role/) | The branch-scoped OIDC identity an application repository assumes to ship its services |
| [`service-secret`](service-secret/) | Secrets Manager secret whose shape Terraform owns and whose values it does not |
| [`inbound-events`](inbound-events/) | FIFO queue, DLQ, overflow bucket and one CMK — the Next inbound-events plane |
| [`work-queue`](work-queue/) | Standard SQS work queue, DLQ and CMK. Not `inbound-events`: no overflow bucket, no FIFO ordering |
| [`sessions-payload-bucket`](sessions-payload-bucket/) | Private versioned SSE-KMS payload storage with metadata-controlled retention |
| [`artifacts-bucket`](artifacts-bucket/) | Versioned SSE-KMS storage for immutable code-intelligence artifacts, plus the presigning role |
| [`app-bucket`](app-bucket/) | Private SSE-KMS bucket, lifecycle expiry, and a managed policy for object access |
| [`ssm-bastion`](ssm-bastion/) | Session Manager jump host for private databases. No key pair, no public address, no ingress |
| [`workflow-bootstrap`](workflow-bootstrap/) | One-shot Fargate task definition for Workflow schema bootstrap |

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

From a live repository's `accounts/<env>/main.tf`, by immutable tag. The
callers are in separate repositories — [impel-infra-dev][dev] and
[impel-infra-prod][prod] — so the `?ref=` is what ties a plan to an exact
revision of this code:

```hcl
module "vpc" {
  source = "git::https://github.com/UseImpel/impel-terraform-modules.git//modules/vpc?ref=v2.0.0"

  name       = "impel-dev"
  cidr_block = "10.10.0.0/16"
}
```

The tag is not optional. Without it `terraform init` resolves the default
branch, so an unrelated merge here silently changes a consumer's plan, and CI
in both live repositories fails the build (`terraform_module_pinned_source`).

Nothing propagates on its own. A merge here changes no account until someone
bumps a `?ref=` in a live repository and opens a PR there — and that PR's plan
shows exactly what the new version does to that one account. Dev and prod
upgrade independently, which is why the two are usually on different versions.

[dev]: https://github.com/UseImpel/impel-infra-dev
[prod]: https://github.com/UseImpel/impel-infra-prod
