variable "name" {
  description = "Role name, e.g. impel-gateway-dev-github-deploy. Prod SEA names its equivalents impel-<service>-sea-github-deploy."
  type        = string

  validation {
    condition     = can(regex("^[a-zA-Z0-9+=,.@_-]{1,64}$", var.name))
    error_message = "name must be a valid IAM role name: at most 64 characters of [a-zA-Z0-9+=,.@_-]."
  }
}

variable "github_repository" {
  description = "Repository allowed to assume this role, as owner/name, e.g. UseImpel/impel-gateway. Any other repository's token fails the trust policy regardless of what its workflow claims."
  type        = string

  validation {
    condition     = can(regex("^[A-Za-z0-9._-]+/[A-Za-z0-9._-]+$", var.github_repository))
    error_message = "github_repository must be owner/name, with no scheme, host or trailing path."
  }
}

variable "github_oidc_ids" {
  description = "Optional immutable GitHub owner and repository IDs. Set both for repositories using GitHub's immutable OIDC subject format. When null, the legacy name-based prefix is derived from github_repository."
  type = object({
    owner_id      = number
    repository_id = number
  })
  default  = null
  nullable = true

  validation {
    condition = var.github_oidc_ids == null || (
      var.github_oidc_ids.owner_id > 0 &&
      floor(var.github_oidc_ids.owner_id) == var.github_oidc_ids.owner_id &&
      var.github_oidc_ids.repository_id > 0 &&
      floor(var.github_oidc_ids.repository_id) == var.github_oidc_ids.repository_id
    )
    error_message = "github_oidc_ids.owner_id and github_oidc_ids.repository_id must both be positive integers."
  }
}

variable "deploy_branch" {
  description = "The one branch whose workflow runs may assume this role. Matched exactly, so a pull request from a fork cannot deploy: only a run on this branch gets a token with the matching subject."
  type        = string
  default     = "dev"

  validation {
    condition     = !can(regex("[*?]", var.deploy_branch))
    error_message = "deploy_branch must name one branch. A wildcard would let any matching ref deploy, which is the boundary this role exists to draw."
  }
}

variable "ecr_repository_arn" {
  description = "The one repository this role may push to. Pass the ecr-repo module's repository_arn."
  type        = string
}

variable "cluster_name" {
  description = "ECS cluster holding the service, used to build the service ARN the deploy grant is scoped to."
  type        = string
}

variable "service_name" {
  description = "The one ECS service this role may update."
  type        = string
}

variable "build_secret_arns" {
  description = "Secrets this role may read at build time, if any. Empty -- the default, and the right answer for a service whose image is built from source alone. A value here widens the role beyond deploying: an image build that reads a secret can also print it, so grant it only for a Dockerfile that genuinely needs one baked in, and name the single secret rather than a prefix. Runtime configuration does not belong here; ECS reads that from the task definition, and this role never needs it."
  type        = list(string)
  default     = []

  validation {
    condition     = alltrue([for a in var.build_secret_arns : can(regex("^arn:aws:secretsmanager:", a))])
    error_message = "Each entry must be a full Secrets Manager ARN. A bare name or a wildcard would scope this grant wider than one secret."
  }
}

variable "pass_role_arns" {
  description = "Roles ECS may be handed when starting a task -- this service's task and execution roles, and nothing else. Empty means the first RunTask fails on iam:PassRole."
  type        = list(string)

  validation {
    condition     = length(var.pass_role_arns) > 0
    error_message = "pass_role_arns needs at least the task execution role, or ECS cannot start a container."
  }
}
