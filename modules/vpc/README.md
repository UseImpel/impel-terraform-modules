# vpc

Two-tier VPC for ECS Fargate workloads.

## Creates

- VPC with DNS support and hostnames enabled
- One public and one private subnet per availability zone
- Internet gateway, one shared public route table
- NAT with Elastic IPs, one for the whole VPC by default (matching prod): managed NAT gateway(s)
  by default, or fck-nat instances with `nat_mode = "instance"`
- Per-subnet private route tables, each defaulting to its NAT
- Interface VPC endpoints for ECR API, ECR DKR, CloudWatch Logs and Secrets Manager,
  behind a security group that accepts `:443` from the VPC CIDR
- S3 gateway endpoint associated with the private route tables
- The default security group, adopted and emptied so nothing can use it
- Optionally, VPC flow logs to CloudWatch with an IAM role

## Call

```hcl
module "vpc" {
  source = "../../modules/vpc"

  name                 = "impel-gateway-${var.environment}"
  cidr_block           = "10.10.0.0/16"
  availability_zones   = ["ap-southeast-1a", "ap-southeast-1b"]
  public_subnet_cidrs  = ["10.10.0.0/22", "10.10.4.0/22"]
  private_subnet_cidrs = ["10.10.8.0/22", "10.10.12.0/22"]
}
```

## Notes

`single_nat_gateway` defaults to `true` because prod SEA runs exactly one NAT gateway for both
private subnets. Setting it to `false` creates one per AZ and removes the cross-AZ dependency, at
roughly the cost of another NAT per zone. Private route tables are per-subnet either way, so the
switch changes only the route target.

The default security group is adopted with no ingress or egress rules. Terraform will show it as
managed; that is intentional and mirrors the `VpcRestrictDefaultSG` custom resource CDK uses in
prod.

The S3 gateway endpoint accepts an optional `s3_gateway_endpoint_policy` — an IAM policy document
bounding what anything in the VPC can do through the endpoint, regardless of its own permissions.
Null, the default, leaves AWS's full-access policy in place. The endpoint's prefix list is exposed
as `s3_gateway_prefix_list_id` for security group rules that allow S3 without opening `0.0.0.0/0`;
it is null when `enable_s3_gateway_endpoint` is false.

## NAT mode: managed gateway or fck-nat instance

`nat_mode` picks how private subnets reach the internet. Both modes create one NAT per VPC
(`single_nat_gateway = true`) or one per AZ, and both send from the same Elastic IPs.

| | `"gateway"` (default) | `"instance"` |
|---|---|---|
| What runs | `aws_nat_gateway` | [fck-nat](https://fck-nat.dev) on `nat_instance_type` (default `t4g.nano`) in an Auto Scaling group of one, 8 GiB encrypted gp3 |
| Private route target | the NAT gateway | a static ENI (`source_dest_check = false`) the instance attaches at boot |
| Cost (ap-southeast-1, per NAT) | about $43/month plus $0.059/GB processed | about $5/month, no per-GB processing charge |
| If it fails | AWS-managed, zonal | the group replaces the instance: **2-3 minutes with no private-subnet egress** (image pulls, Secrets Manager, Logs, third-party APIs all stop) |
| Throughput | up to 100 Gbps | t4g.nano: 32 Mbps baseline, bursting to 5 Gbps |

Prod keeps `"gateway"`. `"instance"` suits a dev VPC, where a few minutes without egress on the
rare replacement is cheaper than $43/month per NAT.

```hcl
module "vpc" {
  # ...
  single_nat_gateway = true
  nat_mode           = "instance"
  # Optional: pin the image outright instead of resolving nat_instance_ami_name.
  # nat_instance_ami_id = "ami-0123456789abcdef0"
}
```

What instance mode creates, per NAT unless noted:

- A security group (one per VPC) accepting all traffic from the VPC CIDR and sending anywhere
- A static ENI in the NAT's public subnet, source/destination check off; the private default
  routes target it, so they never move when the instance is replaced
- An IAM role and instance profile (one per VPC) with `AmazonSSMManagedInstanceCore` for Session
  Manager (no SSH key, no port 22) and just enough EC2 access for fck-nat: attach the static ENI,
  associate the NAT's Elastic IP, turn off source/destination checking. Instance and ENI actions
  are limited to resources carrying the `impel-nat-instance` tag, which the role cannot add
- A launch template: IMDSv2 required (hop limit 1), encrypted gp3 root, user data that writes
  `/etc/fck-nat.conf` (`eni_id`, `eip_id`) and retries the Elastic IP association for up to 15
  minutes
- An Auto Scaling group of exactly one in that subnet (an ENI attaches only within its AZ), with
  an instance refresh (terminate, then launch) whenever the launch template changes. It sets
  `ignore_failed_scaling_activities = true` with a 10 minute `wait_for_capacity_timeout`: the group
  is created seconds after its instance profile, so the first launch can fail with
  "Authentication Failure" while IAM propagates, and the group's own retry a minute later
  succeeds. Without this the provider fails the apply on that first failure and leaves a healthy
  group tainted, which the next apply replaces (another egress gap). A launch that keeps failing
  still fails the apply, after 10 minutes.

**Image.** By default the module resolves the exact AMI name in `nat_instance_ami_name` from the
fck-nat publisher (`nat_instance_ami_owner`, `568608671756`). An exact name, not `most_recent`
over a wildcard, so a new fck-nat build never replaces the instance on an unrelated apply. To move
to a newer build, change the name (or set `nat_instance_ami_id`) in a quiet window: the launch
template change replaces the instance, with the usual 2-3 minute egress gap.

**Boot sequence.** The instance's primary interface gets an auto-assigned public address, which
it needs to call EC2 before it holds the Elastic IP. fck-nat then attaches the static ENI as the
second interface, masquerades out of the primary interface, and associates the NAT's Elastic IP
with it. That association releases the auto-assigned address, so nothing extra is billed in steady
state and traffic leaves from the Elastic IP, as it did from the NAT gateway.

## Keeping the NAT's public IP

Third parties and this estate's own security groups allowlist the NAT address
(`nat_gateway_public_ips`), so a mode switch must not change it.

- **Module-owned EIPs (every caller today).** `aws_eip.nat` exists in both modes. Switching
  `nat_mode` does not touch it: the NAT gateway's deletion releases the association and the fck-nat
  instance takes the same allocation. No `moved` blocks, no imports. `nat_gateway_public_ips`
  (the name predates `nat_mode`) keeps returning the same address.
- **Caller-owned EIPs.** Pass `nat_eip_allocation_ids`, one per NAT, and the module creates no EIP
  of its own. **Do not pass the IDs of EIPs this module already created**: `aws_eip.nat` would
  plan a destroy, and destroying it releases the address for good. To hand an existing
  module-owned EIP to the caller, move it in the same change:

  ```hcl
  resource "aws_eip" "nat" {
    domain = "vpc"
    tags   = { Name = "impel-example-dev-nat-1" }
  }

  moved {
    from = module.vpc.aws_eip.nat[0]
    to   = aws_eip.nat
  }

  module "vpc" {
    # ...
    nat_eip_allocation_ids = [aws_eip.nat.id]
  }
  ```

  The plan must show the move and no `aws_eip` create or destroy. For an EIP allocated outside
  Terraform, pass its allocation ID as-is; nothing needs importing.

**Security group descriptions.** EC2 accepts a security group or rule description only if it is
under 256 characters from `a-zA-Z0-9`, space and `._-:/()#,@[]+=&;{}!$*`, and checks only at
apply. v2.9.0's NAT egress rule had an apostrophe: it planned cleanly, then failed the apply after
the NAT gateway was already gone (fixed in the next patch release). `tests/nat_mode.tftest.hcl`
asserts on this module's rendered descriptions, and `tools/check-sg-descriptions.py` (run by CI)
checks every module's literal ones.

**Recovering from v2.9.0.** If a v2.9.0 apply failed on `nat_instance_all` and the rule was then
added by hand, import it rather than letting the next apply create a duplicate (EC2 rejects a
second identical rule):

```hcl
import {
  to = module.vpc.aws_vpc_security_group_egress_rule.nat_instance_all[0]
  id = "sgr-0123456789abcdef0" # the hand-made rule
}
```

The plan then shows the import plus an in-place description update. If the same apply also
reported "waiting for Auto Scaling Group ... capacity satisfied: ... Authentication Failure", the
group is tainted and the plan replaces it (2-5 minutes with no egress). When the group has a
healthy `InService` instance, `terraform untaint 'module.vpc.aws_autoscaling_group.nat[0]'` before
the apply avoids that; the plan then shows only an in-place update of
`ignore_failed_scaling_activities`.

## Switching modes

`"gateway"` to `"instance"`, as a plan:

- destroy `aws_nat_gateway.this[*]`
- update in place `aws_route.private_default[*]` (target NAT gateway to static ENI, via
  `ReplaceRoute`)
- create the security group and its two rules, the static ENI(s), the IAM role, policy,
  attachment and instance profile, the launch template(s) and the Auto Scaling group(s)

Subnets, route tables, their associations, the S3 gateway endpoint and `aws_eip.nat` must show
no change; anything else in the plan is a bug. Private-subnet egress stops from the route
update until the instance has associated the Elastic IP, typically 2-5 minutes: AWS takes a
minute or two to delete the NAT gateway and release the address, and the user data retries the
association until then. Apply in a quiet window.

Verify afterwards: private tasks start (image pulls, secrets), an in-VPC `curl
https://checkip.amazonaws.com` returns the same address as before, CloudWatch `NatGateway` metrics
stop, and the instance's `/var/log/cloud-init-output.log` (via Session Manager) ends with
`fck-nat: eipalloc-... is on eni-...`.

**Rollback** is `nat_mode = "gateway"`. The plan reverses the one above. Creating the NAT gateway
can race the instance's termination for the Elastic IP; if the apply fails with the address
already associated, re-run it once the Auto Scaling group has terminated the instance (a minute or
so).

