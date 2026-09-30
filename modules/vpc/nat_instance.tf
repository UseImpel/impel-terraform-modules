# NAT instance mode (nat_mode = "instance")
#
# fck-nat (https://fck-nat.dev) on a Graviton instance, in an Auto Scaling
# group of one per NAT. The private route tables target a static ENI that
# outlives the instance; each new instance attaches it at boot, and moves the
# NAT's Elastic IP onto its own primary interface, so neither the route target
# nor the public address changes when the group replaces the instance.

locals {
  nat_instance_count = local.nat_instance_mode ? local.nat_count : 0

  # Applied at launch to the instance and its primary ENI, and set on the
  # static ENI. The instance role's ENI and instance permissions are scoped to
  # it; the role has no ec2:CreateTags, so nothing else can acquire it.
  nat_instance_tag_key = "impel-nat-instance"

  nat_instance_ami_id = local.nat_instance_mode ? coalesce(var.nat_instance_ami_id, one(data.aws_ami.fck_nat[*].id)) : null
}

data "aws_partition" "current" {
  count = local.nat_instance_mode ? 1 : 0
}

data "aws_caller_identity" "current" {
  count = local.nat_instance_mode ? 1 : 0
}

# Resolved by exact name and publisher, not most_recent over a wildcard, so a
# new fck-nat build never changes the launch template (and so never replaces
# the instance) on an unrelated apply. The name is the same in every region.
data "aws_ami" "fck_nat" {
  count = local.nat_instance_mode && var.nat_instance_ami_id == null ? 1 : 0

  owners      = [var.nat_instance_ami_owner]
  most_recent = true

  filter {
    name   = "name"
    values = [var.nat_instance_ami_name]
  }

  filter {
    name   = "architecture"
    values = ["arm64"]
  }
}

resource "aws_security_group" "nat_instance" {
  count = local.nat_instance_mode ? 1 : 0

  name        = "${var.name}-nat-instance"
  description = "NAT instances for ${var.name}: forward anything from inside the VPC to the internet."
  vpc_id      = aws_vpc.this.id

  tags = {
    Name = "${var.name}-nat-instance"
  }
}

resource "aws_vpc_security_group_ingress_rule" "nat_instance_from_vpc" {
  count = local.nat_instance_mode ? 1 : 0

  security_group_id = aws_security_group.nat_instance[0].id
  description       = "Everything from inside the VPC, which the private route tables send here to be translated."

  cidr_ipv4   = var.cidr_block
  ip_protocol = "-1"
}

# A NAT forwards to arbitrary internet destinations; that is its whole job.
# trivy:ignore:AWS-0104 This is the VPC's NAT: it forwards private-subnet traffic to arbitrary internet destinations, exactly as the managed NAT gateway it replaces does. Ingress is limited to the VPC CIDR.
resource "aws_vpc_security_group_egress_rule" "nat_instance_all" {
  count = local.nat_instance_mode ? 1 : 0

  security_group_id = aws_security_group.nat_instance[0].id
  description       = "Translated traffic out to the internet, plus the instance's own calls to EC2 and SSM."

  cidr_ipv4   = "0.0.0.0/0"
  ip_protocol = "-1"
}

# The private route tables' target. Created by Terraform rather than by the
# instance, so it survives instance replacement and the routes never move.
resource "aws_network_interface" "nat" {
  count = local.nat_instance_count

  subnet_id         = aws_subnet.public[count.index].id
  security_groups   = [aws_security_group.nat_instance[0].id]
  source_dest_check = false
  description       = "${var.name} NAT ${count.index + 1}: private route target, attached to the fck-nat instance."

  tags = {
    Name                         = "${var.name}-nat-${count.index + 1}"
    (local.nat_instance_tag_key) = var.name
  }
}

data "aws_iam_policy_document" "nat_instance_assume" {
  count = local.nat_instance_mode ? 1 : 0

  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

data "aws_iam_policy_document" "nat_instance" {
  count = local.nat_instance_mode ? 1 : 0

  #checkov:skip=CKV_AWS_356:ec2:DescribeAddresses accepts no resource-level scoping; AWS requires "*". Every mutating action below is scoped to the NAT's own ENIs, Elastic IPs and tagged instances.

  statement {
    sid       = "ReadAddresses"
    effect    = "Allow"
    actions   = ["ec2:DescribeAddresses"]
    resources = ["*"]
  }

  statement {
    sid     = "AttachStaticEni"
    effect  = "Allow"
    actions = ["ec2:AttachNetworkInterface"]
    resources = [
      for eni in aws_network_interface.nat :
      "arn:${data.aws_partition.current[0].partition}:ec2:${data.aws_region.current.region}:${data.aws_caller_identity.current[0].account_id}:network-interface/${eni.id}"
    ]
  }

  statement {
    sid       = "AssociateNatAddresses"
    effect    = "Allow"
    actions   = ["ec2:AssociateAddress"]
    resources = [for id in local.nat_eip_allocation_ids : "arn:${data.aws_partition.current[0].partition}:ec2:${data.aws_region.current.region}:${data.aws_caller_identity.current[0].account_id}:elastic-ip/${id}"]
  }

  # The instance itself (AttachNetworkInterface) and its primary ENI
  # (AssociateAddress, and fck-nat's ModifyNetworkInterfaceAttribute to turn off
  # source/destination checking) are created by the Auto Scaling group, so
  # their IDs are unknown here. They carry the tag from the launch template.
  statement {
    sid    = "OwnInstanceAndInterfaces"
    effect = "Allow"
    actions = [
      "ec2:AttachNetworkInterface",
      "ec2:AssociateAddress",
      "ec2:ModifyNetworkInterfaceAttribute",
    ]
    resources = [
      "arn:${data.aws_partition.current[0].partition}:ec2:${data.aws_region.current.region}:${data.aws_caller_identity.current[0].account_id}:instance/*",
      "arn:${data.aws_partition.current[0].partition}:ec2:${data.aws_region.current.region}:${data.aws_caller_identity.current[0].account_id}:network-interface/*",
    ]

    condition {
      test     = "StringEquals"
      variable = "aws:ResourceTag/${local.nat_instance_tag_key}"
      values   = [var.name]
    }
  }
}

resource "aws_iam_role" "nat_instance" {
  count = local.nat_instance_mode ? 1 : 0

  name               = "${var.name}-nat-instance"
  assume_role_policy = data.aws_iam_policy_document.nat_instance_assume[0].json
}

resource "aws_iam_role_policy" "nat_instance" {
  count = local.nat_instance_mode ? 1 : 0

  name   = "fck-nat"
  role   = aws_iam_role.nat_instance[0].id
  policy = data.aws_iam_policy_document.nat_instance[0].json
}

# Session Manager shell access for debugging; no SSH key, no port 22.
resource "aws_iam_role_policy_attachment" "nat_instance_ssm" {
  count = local.nat_instance_mode ? 1 : 0

  role       = aws_iam_role.nat_instance[0].name
  policy_arn = "arn:${data.aws_partition.current[0].partition}:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "nat_instance" {
  count = local.nat_instance_mode ? 1 : 0

  name = "${var.name}-nat-instance"
  role = aws_iam_role.nat_instance[0].name
}

resource "aws_launch_template" "nat" {
  #checkov:skip=CKV_AWS_88:The primary interface needs a public address for the first seconds after boot, to call EC2 before it holds the Elastic IP. fck-nat then associates the Elastic IP with that same interface, which releases the auto-assigned address. The instance accepts traffic from the VPC CIDR only.
  count = local.nat_instance_count

  name                   = "${var.name}-nat-${count.index + 1}"
  description            = "fck-nat for ${var.name} NAT ${count.index + 1}."
  image_id               = local.nat_instance_ami_id
  instance_type          = var.nat_instance_type
  update_default_version = true

  iam_instance_profile {
    arn = aws_iam_instance_profile.nat_instance[0].arn
  }

  # The subnet comes from the Auto Scaling group, which pins the static ENI's
  # subnet: an ENI can only attach to an instance in its own AZ. The public
  # address is needed only until fck-nat moves the Elastic IP onto this
  # interface, which releases it (see the checkov skip above).
  network_interfaces {
    device_index                = 0
    associate_public_ip_address = true
    delete_on_termination       = true
    security_groups             = [aws_security_group.nat_instance[0].id]
  }

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
  }

  block_device_mappings {
    device_name = "/dev/xvda"

    ebs {
      volume_size           = var.nat_instance_root_volume_size
      volume_type           = "gp3"
      encrypted             = true
      delete_on_termination = true
    }
  }

  user_data = base64encode(templatefile("${path.module}/templates/nat-instance-user-data.sh.tftpl", {
    name              = "${var.name}-nat-${count.index + 1}"
    region            = data.aws_region.current.region
    eni_id            = aws_network_interface.nat[count.index].id
    eip_allocation_id = local.nat_eip_allocation_ids[count.index]
  }))

  tag_specifications {
    resource_type = "instance"

    tags = {
      Name                         = "${var.name}-nat-${count.index + 1}"
      (local.nat_instance_tag_key) = var.name
    }
  }

  tag_specifications {
    resource_type = "network-interface"

    tags = {
      Name                         = "${var.name}-nat-${count.index + 1}-primary"
      (local.nat_instance_tag_key) = var.name
    }
  }

  tag_specifications {
    resource_type = "volume"

    tags = {
      Name = "${var.name}-nat-${count.index + 1}"
    }
  }

  tags = {
    Name = "${var.name}-nat-${count.index + 1}"
  }
}

# A group of one: if the instance fails its EC2 status checks, the group
# replaces it (about 2-3 minutes, during which private-subnet egress stops).
# A launch template change (new AMI, instance type, user data) starts an
# instance refresh that terminates the instance and then launches its
# replacement: the static ENI can only be attached to one instance at a time.
# Expect the same 2-3 minute egress gap; apply such changes in a quiet window.
resource "aws_autoscaling_group" "nat" {
  count = local.nat_instance_count

  name                      = "${var.name}-nat-${count.index + 1}"
  min_size                  = 1
  max_size                  = 1
  desired_capacity          = 1
  vpc_zone_identifier       = [aws_subnet.public[count.index].id]
  health_check_type         = "EC2"
  health_check_grace_period = 120

  launch_template {
    id      = aws_launch_template.nat[count.index].id
    version = aws_launch_template.nat[count.index].latest_version
  }

  instance_refresh {
    strategy = "Rolling"

    preferences {
      min_healthy_percentage = 0
      max_healthy_percentage = 100
    }
  }

  tag {
    key                 = "Name"
    value               = "${var.name}-nat-${count.index + 1}"
    propagate_at_launch = true
  }
}
