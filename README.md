# impel-terraform-modules

Versioned, reusable Terraform modules for the Impel AWS estate.

This repository holds **blueprints only**. It deploys nothing and owns no
state. The live configurations that call these modules are:

| Repository | Account |
|---|---|
| [impel-infra-dev](https://github.com/UseImpel/impel-infra-dev) | `867264375510` |
| [impel-infra-prod](https://github.com/UseImpel/impel-infra-prod) | `338510628891` |

Program-level docs live in [impel-infra](https://github.com/UseImpel/impel-infra).

## Consuming a module

Modules are consumed by **immutable tag**, never by branch:

```hcl
module "vpc" {
  source = "git::https://github.com/UseImpel/impel-terraform-modules.git//modules/vpc?ref=v1.0.0"

  name = "impel-platform-dev"
  # ...
}
```

The `?ref=` is not optional. Without it, `terraform init` resolves the default
branch, so an unrelated merge here silently changes a consumer's plan — and a
plan a reviewer approved stops matching the code that applies. CI in both live
repositories fails on an unpinned source (`terraform_module_pinned_source`).

The current version is whatever is at the top of
[releases](https://github.com/UseImpel/impel-terraform-modules/releases).

### Taking a new version

Bump the `?ref=` in the consuming repository and open a PR there. The plan on
that PR shows exactly what the new version changes, per account. Dev and prod
upgrade independently and deliberately; nothing here propagates on its own.

## Modules

| Module | Purpose |
|---|---|
| `acm-certificate` | DNS-validated ACM certificate for a load balancer |
| `alb` | Application Load Balancer — `:80` redirects to `:443` |
| `app-bucket` | Private application bucket with its own CMK, TLS-only, versioned |
| `aurora-serverless` | Aurora PostgreSQL Serverless v2 cluster |
| `ecr-repo` | ECR repository with lifecycle policy and optional cross-account pull |
| `ecs-cluster` | Fargate ECS cluster |
| `ecs-service` | One Fargate service, end to end — the workhorse module |
| `github-deploy-role` | Identity an application repo assumes to ship one service |
| `inbound-events` | S3 + CMK + FIFO queue and DLQ for a service's inbound event plane |
| `memorydb` | MemoryDB Redis cluster with TLS and a named ACL user |
| `service-secret` | Secrets Manager secret whose *shape* Terraform owns, not its values |
| `valkey` | ElastiCache Valkey replication group |
| `vpc` | Two-tier VPC for ECS Fargate workloads |
| `workflow-bootstrap` | One-shot Fargate task that runs Workflow schema bootstrap |

Each module has its own README with inputs, outputs, and the live resource it
was shaped after.

## Conventions

- **No environment values.** A module takes names, CIDRs and sizes as inputs;
  it never hardcodes an account, a region, or an environment. If a module needs
  to know whether it is dev or prod, the interface is wrong.
- **No provider blocks.** Modules inherit the provider from the calling root,
  which is what lets one module serve both accounts.
- **No backends.** These are not root configurations.
- **Naming** — resources are named `impel-<component>-<env>` from a prefix
  supplied by the caller.
- **Tagging** — callers set `default_tags` on the provider; modules do not add
  per-resource tag blocks.
- **Write modules against real workloads.** Everything here was extracted from
  the live prod SEA topology. A directory containing a guess at what a resource
  should look like is worse than no directory, because the guess gets copied.

## Cutting a release

Releases are cut by the pipeline, not by hand. **Merge to `main` with a
conventional PR title and the release proposes itself** — the version is
derived from the commits, and the run waits for a `platform-approvers`
approval before the tag exists.

The PR title decides the bump, because the repository squash-merges and the
title becomes the commit subject:

| PR title | Bump | Example |
|---|---|---|
| `fix:` / `perf:` | patch | `fix: correct the alb health check path` |
| `feat:` | minor | `feat: add a multi-az input to memorydb` |
| `feat!:` or a `BREAKING CHANGE:` footer | major | `feat!: drop task_cpu from ecs-service` |
| `docs:` `chore:` `refactor:` `test:` `ci:` `build:` | none | `docs: fix a typo` |

Use `!` whenever a consumer must change more than their `?ref=` — a removed
variable or output, or a default dropped so the variable becomes required.
That is the difference between an upgrade a consumer can take casually and one
that breaks their `terraform init`, and the version number is how they tell.

A PR whose title is not conventional fails CI, so the convention is caught at
review time.

To approve: open the run, read the summary — old version, new version, the
commits behind it and the modules touched — and approve. The tag and release
are created only then. Rejecting leaves nothing behind and does not burn the
version number.

## CI

One workflow, `modules`, runs the whole chain:

```
quality → plan-release → publish (approval) → notify
```

`quality` runs on every PR and push to `main`: `terraform fmt`, then
`terraform validate` per module (with `-backend=false`, since these are not
roots), then TFLint, Trivy and Checkov. On a PR the chain stops there.

`plan-release` derives the next version and stops the run if nothing since the
last tag changes what a consumer gets. `publish` waits for approval, then
creates the tag and the release — in that order, so an unreviewed commit is
never tagged. It will not overwrite an existing release: consumers pin by tag,
so a moved tag would hand them different code under a version they already
reviewed.

A ruleset on `refs/tags/v*` blocks tag creation for everyone except the
release app, which makes this pipeline the only way a `v*` tag can appear. The
app, the `release` environment and that ruleset are repository settings rather
than code — see [`.github/RELEASE_SETUP.md`](.github/RELEASE_SETUP.md).

## Local checks

```sh
pre-commit run --all-files
terraform -chdir=modules/vpc init -backend=false
terraform -chdir=modules/vpc validate
tflint --recursive
```
