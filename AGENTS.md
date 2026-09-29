# AGENTS.md

Versioned, reusable Terraform modules for the Impel AWS estate. **This
repository is public.** No providers, backends, state, account IDs, hostnames
or environment values belong here: every such value is passed in by the
caller (use `123456789012` / `example.com` in docs and tests).

Consumers pin modules by tag (`?ref=vX.Y.Z`) from
[impel-infra-dev](https://github.com/UseImpel/impel-infra-dev) and
[impel-infra-prod](https://github.com/UseImpel/impel-infra-prod).

## Branches, Deploys & Production Releases

This follows the UseImpel infrastructure-repo convention (impel-infra-prod and
impel-infra-dev work the same way; service repos use `dev` instead).

### Branches

- **`main` is the only long-lived branch and the default branch.** It records
  what has been released. Base every PR and worktree on `origin/main`; feature
  branches are deleted on merge.
- `main` is protected: a PR with one approving review (code owners =
  `@UseImpel/platform-approvers`), stale reviews dismissed, linear history, and
  the `quality`, `secret-scan` and `workflow-lint` checks green.

### What a release is here

A release is an **immutable, annotated `vX.Y.Z` tag plus a GitHub Release**
with generated notes. There is no deploy target: a tag changes no account by
itself. Production changes only when an impel-infra-prod PR bumps a `?ref=`,
and that PR's own plan and `aws-prod` apply gate are the production release.

### How a tag is cut (GitOps)

Everything happens in `CI / Modules and release` (`.github/workflows/modules.yml`):

1. **Merge** a PR to `main`. Its **title** is the squash commit subject and
   decides the version (Conventional Commits): `feat` -> minor, `fix`/`perf` ->
   patch, `!` / `BREAKING CHANGE:` -> major; `docs`/`chore`/`ci`/`refactor`/
   `test`/`build` -> no release. `quality` enforces the title format on the PR.
2. `plan-release` checks the commit is on `main`, computes the version from the
   commits since the last tag, and writes the version, commits and changed
   modules to the run summary. It creates nothing.
3. `publish` pauses on the **`release` environment** (reviewers:
   platform-approvers; branch policy: protected branches, i.e. `main`). After
   approval it tags the exact SHA that was checked as `impel-release-bot` and
   creates the GitHub Release.
4. `notify` comments the released version on the merged PR.
5. **Consume** it by bumping `?ref=` in an impel-infra-dev PR first, then in an
   impel-infra-prod PR. **Roll back** by reverting that consumer PR to the
   previous `?ref=`; never by moving or deleting a tag.

The `release tags` tag ruleset (`refs/tags/v*`) blocks creating, updating and
deleting release tags for everyone except `impel-release-bot`, so `publish` is
the only path to a tag. See `.github/RELEASE_SETUP.md`.

### Rules for agents

- **Never push, move or delete a `v*` tag by hand**, and never recreate a tag to
  "re-run" a release. If a release half-failed (tag without release), create
  the release from the existing tag (`.github/RELEASE_SETUP.md`).
- **Before merging, check nobody else is mid-release**: an in-progress or
  waiting `CI / Modules and release` run on `main`
  (`gh run list -R UseImpel/impel-terraform-modules -w modules.yml`). Approving
  a queued `publish` releases everything merged up to that commit.
- **Get the PR title type right.** A `feat` that breaks callers must be `feat!`.
- **Never merge a consumer bump whose plan did not go green**, and read the
  plan for replacements the module change implies (DNS namespaces, target
  groups, task definitions).
- Never run `aws ecs update-service` / `register-task-definition` against prod;
  production is changed only by impel-infra-prod applies.
- Keep this repository free of account-specific data. `secret-scan` (gitleaks,
  full history) runs on every PR, including fork PRs.

The consumer-side runbook, including GitOps service releases, is
"GitOps releases" in impel-infra-prod `docs/service-deployments.md`.

## Checks

```sh
pre-commit run --all-files
terraform fmt -check -recursive
for d in modules/*/; do
  terraform -chdir="$d" init -backend=false && terraform -chdir="$d" validate
  [ -d "$d/tests" ] && terraform -chdir="$d" test
done
tflint --init && tflint --recursive
trivy config --severity HIGH,CRITICAL .
actionlint && zizmor .github/workflows
```

Use Terraform 1.14.x (`TERRAFORM_VERSION` in `modules.yml`); `terraform test`
with `mock_provider` needs >= 1.7.
