# A jump host for reaching private databases from a laptop, with no inbound
# path and no key material: no key pair, no public address, empty ingress.
# The SSM agent dials out over 443, so authorisation is IAM (ssm:StartSession)
# and the audit trail is session history rather than authorized_keys.
#
# Developers run AWS-StartPortForwardingSessionToRemoteHost against it. The
# egress rules below are per-database rather than open because forwarding is
# the whole capability -- the set of reachable hosts *is* the security policy.

data "aws_partition" "current" {}

# Identity. AmazonSSMManagedInstanceCore registers the instance as a managed
# node; managed rather than hand-copied because the actions change with the
# agent. Note the direction: this lets the *instance* talk to SSM and grants
# nobody a session -- that is aws_iam_policy.operator below.

data "aws_iam_policy_document" "assume" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "this" {
  name               = var.name
  description        = "Session Manager access for the ${var.name} jump host."
  assume_role_policy = data.aws_iam_policy_document.assume.json
}

resource "aws_iam_role_policy_attachment" "ssm" {
  role       = aws_iam_role.this.name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "this" {
  name = var.name
  role = aws_iam_role.this.name
}

# Network position
#
# Egress only, and only to the two things the host does: HTTPS so the agent can
# reach the SSM control plane, and the database port so a forwarded session has
# somewhere to land.
#
# HTTPS is the one rule that cannot be narrowed to a security group. Where the
# VPC has interface endpoints for SSM the agent reaches them inside the VPC;
# where it does not, the same traffic leaves through NAT to a public AWS
# endpoint whose addresses are not enumerable. Both are 443 outbound, and
# var.https_egress_cidr is how a caller with endpoints tightens it to the VPC.

resource "aws_security_group" "this" {
  name        = var.name
  description = "Egress-only jump host: ${var.name} reaches SSM and its databases, and accepts nothing."
  vpc_id      = var.vpc_id

  tags = {
    Name = var.name
  }
}

# No aws_vpc_security_group_ingress_rule anywhere in this module, and no
# variable that would add one. Session Manager needs no listening port, so an
# ingress rule here would be an unused hole with a plausible-sounding
# description -- exactly the kind that survives a review years later.

# trivy:ignore:AWS-0104 The SSM agent's control-plane endpoints are public AWS addresses that are not enumerable as CIDRs. A caller whose VPC has the ssm/ssmmessages/ec2messages interface endpoints narrows this to the VPC with var.https_egress_cidr; the port stays 443 either way.
resource "aws_vpc_security_group_egress_rule" "https" {
  security_group_id = aws_security_group.this.id
  description       = "HTTPS to the SSM control plane."

  cidr_ipv4   = var.https_egress_cidr
  from_port   = 443
  to_port     = 443
  ip_protocol = "tcp"
}

# The reachable set, one rule per database. Referenced by security group rather
# than CIDR, so this says "the identity/gateway/... cluster" and keeps saying it
# after a cluster is replaced and its addresses change.
resource "aws_vpc_security_group_egress_rule" "database" {
  for_each = var.database_ingress

  security_group_id = aws_security_group.this.id
  description       = "PostgreSQL to ${each.key}."

  referenced_security_group_id = each.value.security_group_id
  from_port                    = each.value.port
  to_port                      = each.value.port
  ip_protocol                  = "tcp"
}

# The other half of each path, written onto the database's own security group.
#
# This direction is what keeps the graph acyclic, and matches modules/ecs-service:
# data stores are created with no clients and each client grants itself access.
# A store taking a list of client security groups would cycle, because the
# client needs the store's ID to write this rule.
resource "aws_vpc_security_group_ingress_rule" "database" {
  for_each = var.database_ingress

  security_group_id = each.value.security_group_id
  description       = "PostgreSQL from the ${var.name} jump host."

  referenced_security_group_id = aws_security_group.this.id
  from_port                    = each.value.port
  to_port                      = each.value.port
  ip_protocol                  = "tcp"
}

# The instance
#
# Amazon Linux 2023 ships and starts the SSM agent, so there is no user data:
# nothing has to be installed for this host to do its job. Resolved from SSM
# Parameter Store rather than pinned, because a pinned AMI is a host that
# silently ages out of patches, and this one holds no state worth preserving --
# it forwards TCP and can be replaced at any time.

data "aws_ssm_parameter" "ami" {
  name = var.ami_ssm_parameter
}

resource "aws_instance" "this" {
  #checkov:skip=CKV_AWS_135:EBS optimisation is always on and not configurable for t4g; the argument would be a no-op.
  #checkov:skip=CKV_AWS_126:Detailed monitoring bills per instance per month for one-minute metrics nobody reads on a host that idles between sessions. The five-minute default is the right granularity for a jump host.
  ami           = data.aws_ssm_parameter.ami.value
  instance_type = var.instance_type

  subnet_id              = var.subnet_id
  vpc_security_group_ids = [aws_security_group.this.id]
  iam_instance_profile   = aws_iam_instance_profile.this.name

  # A public address would be an inbound path, which is the thing this design
  # is built to not have. Reachability is the SSM agent's outbound connection.
  associate_public_ip_address = false

  # No key_name. A key pair is a second way in, held on laptops, outside the
  # IAM audit trail and impossible to revoke centrally. Session Manager is the
  # only access path by construction rather than by policy.

  # IMDSv2 required: a token-authenticated hop-limited endpoint, so a request
  # tricked out of a process on this host cannot read the role's credentials.
  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
    instance_metadata_tags      = "enabled"
  }

  root_block_device {
    volume_type = "gp3"
    volume_size = var.root_volume_size

    # AWS-managed EBS encryption. A CMK would add a monthly key charge and a
    # grant to manage, and there is nothing on this disk to protect: no
    # database data lands here, only forwarded packets in flight.
    encrypted = true

    delete_on_termination = true
  }

  tags = {
    Name = var.name
  }

  # The AMI parameter resolves to whatever Amazon has published most recently,
  # so without this every plan after a release proposes replacing the host --
  # noise in an unrelated diff, and a session dropped mid-query if applied.
  # Replacement is a deliberate act: taint it, or change instance_type.
  lifecycle {
    ignore_changes = [ami]
  }
}

# Operator access -- the permission a human needs to open a tunnel. Exported
# rather than attached: the consuming principals are SSO permission sets that
# live outside this account, so attaching is the caller's step.
#
# StartSession takes the instance *and* the document, and an allow needs both.
# Naming only the instance would permit any document on it, including
# SSM-SessionManagerRunShell -- a root shell. This grants port forwarding
# alone; ssm:SendCommand is absent for the same reason.
#
# Own-session scoping is by resource ARN: sessions are named
# `<caller>-<suffix>`, so session/$${aws:userid}-* matches the caller's own and
# nobody else's. Without it any holder could kill a colleague's session.

data "aws_iam_policy_document" "operator" {
  #checkov:skip=CKV_AWS_356:The DescribeSessions statement below. Neither ssm:DescribeSessions nor ssm:GetConnectionStatus supports resource-level permissions -- both are account-scoped in the service authorization reference -- so a narrower Resource denies every call. Both are read-only, and the actions that carry data are scoped to this instance and to the caller's own sessions.
  statement {
    sid    = "StartPortForwardingSessionToThisHost"
    effect = "Allow"
    actions = [
      "ssm:StartSession",
    ]
    resources = [
      aws_instance.this.arn,
      "arn:${data.aws_partition.current.partition}:ssm:*:*:document/AWS-StartPortForwardingSessionToRemoteHost",
    ]
  }

  # The channel the forwarded bytes travel over. Without this the session is
  # authorised and then fails as it connects, which reads like a network fault
  # rather than a missing permission.
  statement {
    sid    = "OpenDataChannelForOwnSessions"
    effect = "Allow"
    actions = [
      "ssmmessages:OpenDataChannel",
    ]
    resources = ["arn:${data.aws_partition.current.partition}:ssm:*:*:session/$${aws:userid}-*"]
  }

  # What the CLI checks before connecting. Neither takes a resource, so a
  # resource-scoped statement would deny every call.
  statement {
    sid    = "DescribeSessions"
    effect = "Allow"
    actions = [
      "ssm:DescribeSessions",
      "ssm:GetConnectionStatus",
    ]
    resources = ["*"]
  }

  statement {
    sid    = "ManageOwnSessions"
    effect = "Allow"
    actions = [
      "ssm:TerminateSession",
      "ssm:ResumeSession",
    ]
    resources = ["arn:${data.aws_partition.current.partition}:ssm:*:*:session/$${aws:userid}-*"]
  }
}

resource "aws_iam_policy" "operator" {
  name        = "${var.name}-operator"
  description = "Open a port-forwarding session to ${var.name}. Grants no shell on the host."
  policy      = data.aws_iam_policy_document.operator.json
}
