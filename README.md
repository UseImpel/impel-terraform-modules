# impel-infra-main

Terraform infrastructure-as-code for the Impel AWS estate, deployed exclusively
through GitHub Actions. One directory per AWS account.

| Account | ID | State bucket | Apply gate |
|---|---|---|---|
| Impel (DEV) | `867264375510` | `impel-tfstate-dev` | `aws-dev` — any team member |
| Impel (production) | `338510628891` | `impel-tfstate-prod` | `aws-prod` — `platform-approvers`, no self-approval |

Region `ap-southeast-1` (Singapore). Terraform `>= 1.10` for S3-native state
locking. Production is also the AWS Organizations management account.

## Layout

```
accounts/                 Live deployments. One directory = one AWS account.
  dev/                    → 867264375510
  prod/                   → 338510628891
  shared-services/        → placeholder; the account does not exist yet

modules/                  Reusable blueprints, called by relative path. No
                          hardcoded environment values — see modules/README.md.

scripts/
  bootstrap-account.sh    Creates the state backend and CI roles via the AWS
                          CLI. Deliberately NOT Terraform — see below.

docs/bootstrap.md         What the bootstrap layer creates and how to verify it.
docs/service-deployments.md
                          How application code reaches a running service, and
                          which side owns which half.
```

An account directory is five files — `backend.tf`, `providers.tf`,
`variables.tf`, `versions.tf`, `main.tf` — and `main.tf` is composition only:
it calls modules, it does not define resources.

```hcl
module "vpc" {
  source = "../../modules/vpc"

  environment = var.environment
  cidr_block  = "10.10.0.0/16"
}
```

`accounts/dev` holds a scaled-down replica of the four prod SEA services —
gateway, next, identity and sessions — behind one shared load balancer. See
[`docs/dev-sea-replica-status.md`](docs/dev-sea-replica-status.md) for what is
running and what is left. `accounts/prod` manages four ECR repositories and
nothing else; the rest of that account is still CDK-owned.

## Deployment model

Nobody runs `terraform apply` from a laptop.

```
push (any branch)
  └─ lint ──────────► fmt · validate · tflint · trivy · checkov

pull request → main
  ├─ lint                                                    [required check]
  ├─ plan ──────────► terraform plan → posted as a PR comment
  │                   (on failure, the error output is posted too)
  └─ review approval + CODEOWNERS

merge to main
  └─ plan  ─────────► fresh plan from the merged commit, saved as an artifact
     ⏸  manual approval on the aws-<env> environment
     └─ apply ──────► terraform apply <saved plan>
```

The apply job consumes the **saved binary plan file**, so what a reviewer
approves is byte-for-byte what executes.

### One pipeline per environment

Dev and prod have separate workflows, not one matrix over both:

```
.github/workflows/
  lint.yml         shared — no AWS credentials, runs with -backend=false
  _plan.yml        reusable: the plan logic, called by both
  _apply.yml       reusable: the plan → gate → apply logic, called by both
  plan-dev.yml     accounts/dev/**   → DEV_PLAN_ROLE_ARN
  apply-dev.yml    accounts/dev/**   → aws-dev  gate
  plan-prod.yml    accounts/prod/**  → PROD_PLAN_ROLE_ARN
  apply-prod.yml   accounts/prod/**  → aws-prod gate
```

Each environment owns its `concurrency` group, so **a prod apply waiting on a
reviewer can never hold up a dev apply**. Under the old shared matrix
(`max-parallel: 1`) it could, and did. The `_`-prefixed files hold the logic so
a fix lands in one place instead of four; the per-environment files are ~30
lines of wiring each.

Only the account a PR touches is planned. A change under `modules/` or
`.github/actions/` triggers **both** pipelines independently, because shared
code reaches every account.

### Why the gate is enforced by IAM, not just GitHub

Each apply role's trust policy accepts exactly one OIDC subject:
`repo:UseImpel/impel-infra-main:environment:aws-<env>`. GitHub issues a token
with that subject **only after** the environment's reviewer gate passes. A
workflow that skips the gate cannot obtain apply credentials — even if someone
edits the workflow file. The gate is a property of the cloud, not of a YAML
file.

Dev and prod differ only in who may approve:

| | `aws-dev` | `aws-prod` |
|---|---|---|
| Reviewers | `@UseImpel/fde` (whole team) | `@UseImpel/platform-approvers` |
| Self-approval | allowed | blocked |
| Effect | one click, fast feedback | two distinct humans |

## Bootstrap is not Terraform

Terraform cannot create the bucket it stores its own state in, nor the role it
assumes in order to run. That layer — OIDC provider, state bucket, KMS CMK,
plan and apply roles — is created by `scripts/bootstrap-account.sh` with the
AWS CLI.

The script is idempotent: re-running it is how you repair drift, and it is safe
to run at any time. Read [`docs/bootstrap.md`](docs/bootstrap.md) before
touching it — it also documents the two `Deny` statements that stop an apply
from destroying its own state or removing its own gate.

## Brownfield note

The production account already runs CDK stacks (`impelbuzz`, `impelsea`), ECS
services, ALBs, ~20 buckets and seven `*-github-deploy` roles. **None of it is
managed here.** Terraform will not adopt or destroy anything it did not create.
Existing resources are adopted one `import` block at a time, with a plan
showing `0 to add, 0 to change, 0 to destroy` before anyone trusts it.

## Linting before you push

Requires Python 3.9+ and Terraform on your `PATH`.

**Setup — once per clone:**

```bash
pip install pre-commit
pre-commit install          # optional: also run on every `git commit`
```

**Run:**

```bash
pre-commit run --all-files
```

The first run downloads the hook environments and takes a minute or two; after
that it is a few seconds. Most failures are **auto-fixed** — the hook rewrites
the file and reports `Failed`. Re-run to confirm it passes, then commit the
result. Bypass a single commit with `git commit --no-verify`.

### Deeper checks run in CI

`pre-commit` covers formatting only. The `lint` workflow additionally runs
`terraform validate`, `tflint`, `trivy` and `checkov` — it is a required check,
so a PR cannot merge until it is green.

To run those locally (each tool is a separate install):

```bash
# terraform validate — no AWS credentials needed, touches no state
terraform -chdir=accounts/dev init -backend=false
terraform -chdir=accounts/dev validate

# checkov
pip install checkov
checkov -d . --framework terraform --compact --quiet

# tflint and trivy
choco install tflint trivy      # Windows
brew install tflint trivy       # macOS
tflint --init && tflint --recursive --format compact
trivy config . --severity HIGH,CRITICAL
```

If Checkov flags something you have deliberately accepted, add a skip **inside**
the resource block with a reason — placed above the block it is silently
ignored:

```hcl
resource "aws_s3_bucket" "example" {
  #checkov:skip=CKV_AWS_18:Access logging needs a second bucket; CloudTrail covers this.
  bucket = "..."
}
```

## Conventions

- **Naming** — `impel-<component>-<env>`; CI roles follow
  `impel-infra-<env>-github-<purpose>`.
- **Tagging** — applied once via provider `default_tags` and inherited by every
  resource: `ManagedBy`, `Repository`, `Environment`, `Owner`. No per-resource
  tag blocks.
- **Guardrail** — every account sets `allowed_account_ids`, so Terraform
  refuses to run against the wrong account rather than silently applying dev
  config to prod.
- **Modules** — typed variables with `description` and `validation`; every
  module ships a `README.md` and `versions.tf`. No hardcoded account IDs,
  regions or environment names.
- **State** — one state file per account, in that account's own bucket. Never
  commit state or `.tfvars`.

## Adding an account

See [`docs/bootstrap.md`](docs/bootstrap.md#adding-an-account).

It needs two new workflow files — copy `plan-dev.yml` and `apply-dev.yml` and
change the environment, directory and variable names. That is deliberate: an
account is not deployable until someone has decided who approves its applies,
and a copied file makes that decision visible in review. The alternative,
auto-discovery, silently gave a new directory a pipeline.
