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

Risk policy: `pr-risk-v1`

## Risk assessment

Use `low`, `medium`, or `high` with a reason, separated by space-hyphen-space.
Choose one hazard class: `other`, `production-control`, or `destructive-irreversible`.
The last two mean production IAM/network control or destructive/irreversible state operations.
They require independent review and external human acceptance.

- Level and rationale:
- Hazard class:
- Failure mode and blast radius:
- Mitigation, evidence and gaps:
- Rollback limits and residual risks:

## Risk adversary

Require independent review for infrastructure impact, uncertain impact, high risk, or risk-policy/agent-rule changes.
Use `needs-independent-review` when it is missing.
Enter literal tokens without Markdown formatting; use lowercase full SHAs.

Use mode `self`, `independent-agent`, or `independent-human`.
Use state `self-reviewed`, `independent-reviewed`, or `needs-independent-review`.
Record full head/base SHAs from the reviewed comparison; base means the PR base SHA, not merge-base.
For independent review, link the separate review run or human review through HTTPS or `t3-thread://`.
Report missing evidence with a reason; never invent a review or test.

- Reviewer:
- Mode:
- Reviewed head:
- Reviewed base:
- Review state:
- Strongest objection:
- Response:
- Review evidence:

For production-control or destructive-irreversible hazards, add `- Owner acceptance: external-required` here.
This field requires actual non-author human acceptance before merge, even when added voluntarily.
It never records approval; use existing native human approval mechanisms.

For low/no/other changes without governance-control edits, you may replace the expanded adversary fields with this compact form.
Use nonempty values without semicolons or newlines.
Keep owner acceptance separate when present.

```text
- Adversary: reviewer=<id>; mode=self; head=<full-sha>; base=<full-sha>; state=self-reviewed; objection=<text>; response=<text>
```

## Infrastructure impact

Use `yes`, `no`, or `uncertain` with a reason, separated by space-hyphen-space.
For `yes` or `uncertain`, complete all four fields below.
For `no`, remove the four empty fields.
Report plan-not-run gaps explicitly; a revert does not restore deleted data.
Do not include secrets, customer content, or raw plans.

- Impact and rationale:
- Scope:
- Plan/state:
- Consequences:
- Delivery:

Scope names resources, environments, and consumers.
Plan/state names add/change/destroy/replace effects and the plan revision/environment/reference, or the plan gap and responsible follow-up.
Consequences cover IAM/network/secrets, security/data, availability, and cost.
Delivery covers rollout order, rollback limits, and existing owner/approval/apply gates.
