#!/usr/bin/env python3
"""Fail on security group descriptions that EC2 will reject at apply time.

EC2 accepts a security group or security group rule description only if it is
under 256 characters drawn from a-zA-Z0-9, space and ._-:/()#,@[]+=&;{}!$*.
Nothing checks this at plan: `terraform validate`, the provider and a mocked
`terraform test` all accept an apostrophe or an en dash, and the apply then
fails half way through (vpc v2.9.0 did exactly that with "instance's").

This scans every `description = "..."` inside the security group resources in
modules/, and inside their inline ingress/egress blocks. Interpolations
(`${...}`) are caller input, not literal text, and are skipped; the vpc module's
tests assert on its rendered descriptions as well.

Usage: tools/check-sg-descriptions.py [root ...]   (default: modules)
"""

import pathlib
import re
import sys

SG_RESOURCE_TYPES = {
    "aws_security_group",
    "aws_security_group_rule",
    "aws_vpc_security_group_ingress_rule",
    "aws_vpc_security_group_egress_rule",
}

ALLOWED = re.compile(r"[a-zA-Z0-9. _\-:/()#,@\[\]+=&;{}!$*]")
MAX_LENGTH = 255

RESOURCE = re.compile(r'^resource\s+"([^"]+)"\s+"[^"]+"')
DESCRIPTION = re.compile(r'^\s*description\s*=\s*"(.*)"\s*$')
INTERPOLATION = re.compile(r"\$\{[^}]*\}")


def check(path: pathlib.Path) -> list[str]:
    problems = []
    resource_type = None
    for number, line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
        match = RESOURCE.match(line)
        if match:
            resource_type = match.group(1)
        elif line.startswith("}"):
            resource_type = None
            continue

        if resource_type not in SG_RESOURCE_TYPES:
            continue

        match = DESCRIPTION.match(line)
        if not match:
            continue

        literal = INTERPOLATION.sub("", match.group(1))
        bad = sorted({c for c in literal if not ALLOWED.fullmatch(c)})
        if bad:
            problems.append(
                f"{path}:{number}: {resource_type} description has characters EC2 rejects: "
                + " ".join(repr(c) for c in bad)
            )
        if len(match.group(1)) > MAX_LENGTH:
            problems.append(f"{path}:{number}: {resource_type} description is over {MAX_LENGTH} characters")
    return problems


def main() -> int:
    roots = [pathlib.Path(p) for p in (sys.argv[1:] or ["modules"])]
    files = sorted(f for root in roots for f in root.rglob("*.tf"))
    problems = [p for f in files for p in check(f)]
    for problem in problems:
        print(f"::error::{problem}")
    if problems:
        print(
            "Allowed: a-zA-Z0-9, space and ._-:/()#,@[]+=&;{}!$* (under 256 characters). "
            "Rephrase rather than escape: no apostrophes, quotes, '>' or non-ASCII dashes."
        )
        return 1
    print(f"Checked security group descriptions in {len(files)} files: all valid.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
