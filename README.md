# impel-terraform-modules

Versioned, reusable Terraform modules for the Impel AWS estate. This repository
contains blueprints only: no providers, backends, state, or environment values.

Consumers:

- [impel-infra-dev](https://github.com/UseImpel/impel-infra-dev)
- [impel-infra-prod](https://github.com/UseImpel/impel-infra-prod)

## Use a module

Pin every source to an immutable release tag:

```hcl
module "vpc" {
  source = "git::https://github.com/UseImpel/impel-terraform-modules.git//modules/vpc?ref=v2.0.0"
  # ...
}
```

A module release changes no account by itself. Bump its tag in a reviewed
consumer PR; that PR owns the resulting plan.

## Modules

Networking: `vpc`, `alb`, `acm-certificate`, `private-dns-namespace`.

Compute: `ecs-cluster`, `ecs-service`, `meets-service`, `engine-tasks`,
`workflow-bootstrap`, `ssm-bastion`.

Data and storage: `aurora-serverless`, `valkey`, `memorydb`, `efs-volume`,
`app-bucket`, `artifacts-bucket`, `sessions-payload-bucket`, `ecr-repo`,
`service-secret`, `inbound-events`, `work-queue`.

Identity: `github-deploy-role`.

Each module documents its inputs and outputs in its own README.

## Checks

```sh
pre-commit run --all-files
terraform -chdir=modules/vpc init -backend=false
terraform -chdir=modules/vpc validate
tflint --recursive
```
