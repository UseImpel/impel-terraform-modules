# service-secret

A Secrets Manager secret whose **shape** Terraform manages and whose **values** it does not.

Prod services read individual keys from one runtime secret using the `secret-arn:KEY::` reference
form — identity pulls around 80 keys this way. Every key a task definition names must exist in the
JSON or the task fails to start. This module seeds those keys empty, then ignores the contents
forever.

## Creates

- `aws_secretsmanager_secret` — and nothing inside it

Terraform manages the secret's existence, name, KMS key and tags. It does **not** manage any
version, and never reads the contents.

## Call

```hcl
module "gateway_runtime_secret" {
  source = "../../modules/service-secret"

  name        = "impel-gateway-${var.environment}/runtime"
  description = "Runtime configuration for the gateway service."
  keys        = ["PG_HOST", "PG_USER", "PG_PASSWORD", "CRON_SECRET"]
}
```

Then wire it into the service:

```hcl
module "gateway_service" {
  source = "../../modules/ecs-service"

  container_secrets = module.gateway_runtime_secret.container_secrets
  # ...
}
```

## Seeding values

A newly created secret has **no version at all**, so every key a task definition references must be
written before the service will start. The `seed_command` output gives you the exact call — it
expands to a `put-secret-value` writing every expected key as an empty string, establishing the JSON
shape. Then replace the empty strings with real values:

```sh
aws secretsmanager put-secret-value   --secret-id impel-gateway-dev/runtime   --secret-string file://runtime.json
```

Adding a key later means adding it to `keys` **and** re-running `put-secret-value` with the full
JSON — there is no merge, the whole document is replaced.

## Why Terraform manages no version

An earlier version of this module created a placeholder `aws_secretsmanager_secret_version` holding
empty strings, with `ignore_changes = [secret_string]`.

That was wrong in a way only CI revealed. `ignore_changes` suppresses the *diff*, not the
*refresh* — so every plan still called `secretsmanager:GetSecretValue`. AWS's `ReadOnlyAccess`
managed policy deliberately withholds that action, precisely so a read-only role cannot read
secrets. The result was that every `plan-dev` run failed with `AccessDeniedException`.

Granting the permission would have meant letting a read-only CI role read every secret in the
account, to support a resource whose only job was to write empty strings. Removing the resource is
the smaller and safer change: the plan role needs no secret access, and no secret value can reach a
plan log or the state file.

The trade is that secret *shape* is no longer enforced by Terraform. The `expected_keys` and
`seed_command` outputs make the contract explicit instead.

## Notes

`recovery_window_days` defaults to 30. Set it to `0` in dev so a destroyed secret's name is
immediately reusable; otherwise a re-apply fails for a week with `InvalidRequestException: already
scheduled for deletion`.
