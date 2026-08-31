# ssm-bastion

A jump host for reaching private databases from a laptop, with no inbound path
and no key material.

The instance has no key pair, no public address and an empty ingress list.
Access is Session Manager: the SSM agent dials the control plane outbound over
443 and a session is a stream on that connection, so nothing ever needs to
reach the host. Authorisation is IAM, and the audit trail is the SSM session
history rather than an `authorized_keys` file nobody prunes.

What developers run against it is
`AWS-StartPortForwardingSessionToRemoteHost`, which makes a database that only
exists on a private subnet appear on `localhost` — enough for pgAdmin, `psql`,
or any other client that speaks the wire protocol.

## Creates

- `aws_instance` — no public IP, no key pair, IMDSv2 required, encrypted gp3 root
- `aws_iam_role` + `aws_iam_instance_profile` with `AmazonSSMManagedInstanceCore`
- `aws_iam_policy` granting a human port-forwarding access — exported, not
  attached; see [Who may connect](#who-may-connect)
- `aws_security_group` with **no ingress rules at all**
- Egress `:443` for the agent, plus one egress rule per entry in `database_ingress`
- The matching ingress rule on each database's own security group

## Call

```hcl
module "bastion" {
  source = "../../modules/ssm-bastion"

  name      = "impel-bastion-${var.environment}"
  vpc_id    = module.vpc.vpc_id
  subnet_id = module.vpc.private_subnet_ids[0]

  database_ingress = {
    for service, db in module.postgres : service => {
      security_group_id = db.security_group_id
      port              = db.port
    }
  }
}
```

Then, from a laptop with the [Session Manager
plugin](https://docs.aws.amazon.com/systems-manager/latest/userguide/session-manager-working-with-install-plugin.html)
installed:

```sh
aws ssm start-session \
  --target "$(terraform output -raw bastion_instance_id)" \
  --document-name AWS-StartPortForwardingSessionToRemoteHost \
  --parameters '{"host":["<cluster endpoint>"],"portNumber":["5432"],"localPortNumber":["5432"]}'
```

The session holds the terminal open. Point the client at `localhost:5432`.

## The reachable set

`database_ingress` is the security boundary. Port forwarding is limited by
nothing else — a session names any host and port it likes, and the only reason
one fails is that this security group will not carry the packet. A database
absent from the map is unreachable; adding one is a reviewable Terraform
change rather than a flag on a command line.

Entries reference security groups, not CIDRs, so a rule keeps meaning "the
identity cluster" after that cluster is replaced and its addresses change.

The direction matters: this module writes the ingress rule onto the database's
group rather than the database accepting a list of clients. That is what keeps
the graph acyclic, and matches how [`ecs-service`](../ecs-service/) grants
itself access through `data_store_ingress`. A store taking a list of clients
would cycle, because the client needs the store's ID to write the rule.

## Reaching SSM

The agent must reach the control plane or the instance never registers, and an
unregistered instance is not a valid `--target`. Two ways, and the module works
with either:

| Path | Cost | `https_egress_cidr` |
|---|---|---|
| NAT gateway (default) | The NAT the VPC already has | leave at `0.0.0.0/0` |
| `ssm`, `ssmmessages`, `ec2messages` interface endpoints | Three endpoints × AZs, billed hourly | the VPC CIDR |

Endpoints are worth it when a VPC has no NAT gateway, or when policy forbids
the traffic leaving. Where a NAT already exists for other reasons, they cost
substantially more per month than this instance does, to carry a few megabytes
a day of agent heartbeat.

`0.0.0.0/0` on 443 is the honest expression of the default: the SSM endpoints
are public AWS addresses and are not enumerable as CIDRs.

## Who may connect

Two different permissions, and it is worth keeping them apart:

- The **instance role** lets the host talk to SSM. Without it the host never
  registers and is not a valid target.
- The **operator policy** lets a human open a session. Without it every
  `start-session` returns `AccessDeniedException`.

This module creates both. `operator_policy_arn` is the second one:

```hcl
# Wherever your developer identities are defined -- an SSO permission set,
# a role in another account, an IAM group.
managed_policy_arns = [module.bastion.operator_policy_arn]
```

**Nobody can connect until it is attached.** The module cannot do that itself:
the principal is usually an Identity Center permission set living outside the
account this is applied to. It is exported for the same reason
[`app-bucket`](../app-bucket/) exports `iam_policy_arn` — the module owns the
policy document, the caller owns the attachment.

The policy is scoped harder than the obvious version:

| | |
|---|---|
| `ssm:StartSession` | this instance **and** `AWS-StartPortForwardingSessionToRemoteHost` |
| `ssmmessages:OpenDataChannel` | `session/${aws:userid}-*` |
| `ssm:TerminateSession` / `ResumeSession` | `session/${aws:userid}-*` |
| `ssm:DescribeSessions` / `GetConnectionStatus` | `*` — neither takes a resource |

`StartSession` needs the instance *and* the document, and an allow needs both.
Naming only the instance would permit any document on it, including
`SSM-SessionManagerRunShell` — an interactive shell as root. Port forwarding
carries TCP and offers no way to run a command, so this grants the tunnel and
nothing else. `ssm:SendCommand` is absent for the same reason.

Own-session scoping is by resource ARN rather than condition: a session is
named `<caller>-<suffix>`, so `session/${aws:userid}-*` matches the caller's
own and nobody else's. Without it, any holder could terminate a colleague's
session mid-query.

Do not skip `ssmmessages:OpenDataChannel`. The session is authorised and then
fails as it connects, which reads like a network fault rather than a missing
permission.

## The AMI

Resolved from an SSM public parameter rather than pinned, so a rebuild picks up
a patched image. The instance then ignores later changes to it: without that,
every plan after an Amazon release proposes replacing the host, which is noise
in unrelated diffs and a dropped session if applied.

Replacement is therefore deliberate — taint the instance. Nothing is stored on
it, so replacing it costs a reconnect and nothing else.

`instance_type` and `ami_ssm_parameter` must agree on architecture. Both
default to Graviton; changing one without the other produces an instance that
will not launch.
