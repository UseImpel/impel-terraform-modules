# Security Policy

## Reporting a vulnerability

Do **not** open a public issue. This repository is public and its modules are
used by Impel's production AWS account.

Report privately through GitHub's
[private vulnerability reporting](https://github.com/UseImpel/impel-terraform-modules/security/advisories/new).
Include the affected module(s) and release tag(s), the impact, and steps to
reproduce. We acknowledge reports within two business days.

## Supported versions

Only the latest release tag (`vX.Y.Z`, cut from `main` by the
`CI / Modules and release` workflow) is supported. Fixes ship as a new tag;
existing tags are immutable and are never moved or re-published. Consumers
take a fix by bumping their `?ref=`.
