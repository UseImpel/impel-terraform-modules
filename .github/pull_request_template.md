<!--
The PR title becomes the squash-merge subject, and plan-release derives the
next version from it (Conventional Commits):
  feat: ...  -> minor release     fix: / perf: ... -> patch release
  feat!: ... or a BREAKING CHANGE: footer -> major release
  docs: / chore: / ci: / refactor: / test: / build: -> no release
-->

## What changes for a consumer

<!-- Which modules, what a caller sees differently, and whether an existing
     `?ref=` bump needs configuration changes or only the new tag. -->

## Plan impact

<!-- Expected plan in impel-infra-dev / impel-infra-prod when the tag is bumped
     (resources replaced/updated/destroyed). Call out any replacement. -->

## Checklist

- [ ] PR title is a Conventional Commit with the right type (it decides the version)
- [ ] `terraform fmt -recursive`, `terraform validate` and (if the module has `tests/`) `terraform test` pass locally
- [ ] Module README updated for new/changed inputs and outputs
- [ ] No account IDs, hostnames, secrets or environment values hard-coded (this repository is public)
- [ ] Breaking changes are marked `!` / `BREAKING CHANGE:` and the migration is described above
