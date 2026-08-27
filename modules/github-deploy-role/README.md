# github-deploy-role

The identity an application repository assumes to ship one service: push an image, roll it onto the
running service. No access keys anywhere — GitHub mints a short-lived OIDC token and AWS decides
whether to honour it.

## Creates

- `aws_iam_role` — trusting exactly one repository and branch
- `aws_iam_role_policy` — scoped to one ECR repository and one ECS service

## Call

```hcl
module "gateway_deploy" {
  source = "../../modules/github-deploy-role"

  name              = "impel-gateway-dev-github-deploy"
  github_repository = "UseImpel/impel-gateway"
  deploy_branch     = "dev"

  ecr_repository_arn = module.service_ecr["gateway"].repository_arn
  cluster_name       = module.ecs_cluster.cluster_name
  service_name       = module.service["gateway"].service_name
  pass_role_arns     = module.service["gateway"].role_arns
}
```

The account's GitHub OIDC provider must already exist. `scripts/bootstrap-account.sh` creates it,
and there can only be one per issuer per account — this module reads it, never creates it.

Repositories created on or after 2026-07-15 may use GitHub's immutable OIDC subject format, which
includes the owner and repository IDs. Pass the owner and repository IDs when the repository is
configured for it; otherwise the module derives the legacy name-based prefix from
`github_repository`:

```hcl
github_repository          = "UseImpel/impel-sessions"
github_oidc_ids            = {
  owner_id      = 283797627
  repository_id = 1304531882
}
```

The IDs must both be positive. The module derives the prefix from the owner/name in
`github_repository`, appends `:ref:refs/heads/<deploy_branch>`, and still uses an exact
(`StringEquals`) trust condition.

## Using it from the application repository

```yaml
permissions:
  id-token: write      # without this the runner gets no OIDC token at all
  contents: read

steps:
  - uses: aws-actions/configure-aws-credentials@v4
    with:
      role-to-assume: <role_arn output>
      aws-region: ap-southeast-1
  - uses: aws-actions/amazon-ecr-login@v2
  - run: |
      docker build -t "$REGISTRY/impel-gateway/dev:latest" .
      docker push "$REGISTRY/impel-gateway/dev:latest"
      aws ecs update-service --cluster impel-gateway-dev \
        --service impel-gateway-dev --force-new-deployment
```

The workflow must be triggered by `deploy_branch`. A run on any other ref receives a token with a
different subject and STS refuses it.

## Why the branch is a property of the cloud

The trust policy accepts one subject. For a legacy repository it is:

```
repo:UseImpel/impel-gateway:ref:refs/heads/dev
```

For an immutable-subject repository, it is instead:

```
repo:UseImpel@283797627/impel-sessions@1304531882:ref:refs/heads/dev
```

GitHub puts the ref that triggered the run into the token and signs it. A workflow cannot claim a
subject it was not run under, so **editing the YAML cannot widen this** — the branch restriction
holds even against someone with write access to the application repository.

`StringEquals`, deliberately, not `StringLike`. A wildcard subject would let any branch deploy,
including one pushed by a fork's pull request. Same reasoning as the apply roles in
[`../../docs/bootstrap.md`](../../docs/bootstrap.md), where the environment gate is enforced by the
trust policy rather than by the workflow.

## Scope

Every grant names one resource, except three that AWS will not let you scope:

| Action | Why `*` |
|---|---|
| `ecr:GetAuthorizationToken` | The API rejects any resource. The token it returns is still bounded by the repository grants. |
| `ecs:RegisterTaskDefinition` | A family does not exist until its first revision, so there is nothing to name. Registering is harmless without `UpdateService` and `PassRole`, both of which are scoped. |
| `ecs:DescribeTaskDefinition`, `ListTasks`, `logs:*` | Read-only, and revision ARNs carry no per-service prefix to match on. |

`iam:PassRole` is the one that matters, and it is scoped to this service's task and execution roles
with a `PassedToService` condition. Without that condition a role could be passed to any service that
accepts one; without the grant at all, ECS cannot start a container and the deploy fails on the first
`RunTask`.

The result: a role that deploys the gateway cannot touch identity. A compromised application
repository reaches its own service and stops.

### Build secrets

`build_secret_arns` is empty by default and should stay that way. It exists for a Dockerfile that
must bake a value into the image — `next` inlines its `NEXT_PUBLIC_*` configuration into client
bundles at compile time, so those values have to exist before there is a task to read them.

It is the only grant here that reads data rather than moving an image, and the trade is real: a
build that can read a secret can also print it, and the workflow file decides what the build does.
The boundary is the ARN list, which names exact secrets and rejects anything that is not a full
Secrets Manager ARN — a prefix would grow silently as secrets are added. Runtime configuration does
not belong here; ECS reads that from the task definition and this role never needs it.

## Notes

`max_session_duration` is one hour — long enough for a slow image build, short enough to bound a
leaked token.

This role does **not** grant `secretsmanager:PutSecretValue`. Prod's equivalent does, because its
pipeline writes runtime configuration; here Terraform owns secret shape and values are seeded out of
band. Add it scoped to the one secret ARN if a repository needs to write its own.

Pair with `continuous_deployment = true` on [`../ecs-service`](../ecs-service). Without it, Terraform
reconciles the task definition and the next apply reverts whatever this role deployed.
