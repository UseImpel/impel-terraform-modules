# ecr-repo

One ECR repository with a lifecycle policy and optional cross-account pull access. Matches the
`impel-<service>/sea` repositories in prod: immutable tags, scan on push, AES256.

## Creates

- `aws_ecr_repository`
- `aws_ecr_lifecycle_policy` — expires untagged images, optionally caps tagged image count
- `aws_ecr_repository_policy` — pull-only, when `pull_account_ids` is non-empty

## Call

```hcl
module "ecr_gateway" {
  source = "../../modules/ecr-repo"

  name         = "impel-gateway/${var.environment}"
  force_delete = true # dev only
}
```

Granting a dev account pull access to a prod-owned repository:

```hcl
module "ecr_gateway" {
  source = "../../modules/ecr-repo"

  name             = "impel-gateway/sea"
  pull_account_ids = ["867264375510"]
}
```

## Notes

Services reference images **by digest** (`repository_url` + `@sha256:...`), never by tag — that is
what prod does and it is what makes `IMMUTABLE` meaningful. The digest is supplied to
[`../ecs-service`](../ecs-service) as `container_image`.

The cross-account policy grants pull actions only. A dev account reading prod-built images cannot
push over them.

`force_delete` defaults to `false`. Set it in dev so `terraform destroy` is not blocked by images
sitting in the repository; leave it alone anywhere real.
