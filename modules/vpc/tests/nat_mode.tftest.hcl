# NAT contract. The default nat_mode = "gateway" must render exactly what
# callers had before nat_mode existed (module-owned EIPs, managed NAT gateways,
# private routes to them, no instance resources), so a ?ref= bump plans
# nothing. nat_mode = "instance" must keep the same EIPs (so the public IP does
# not change), keep subnets and route tables, and point every private route at
# a static source/dest-check-free ENI that an fck-nat Auto Scaling group of one
# attaches.

mock_provider "aws" {
  override_during = plan

  mock_data "aws_region" {
    defaults = {
      id     = "ap-southeast-1"
      name   = "ap-southeast-1"
      region = "ap-southeast-1"
    }
  }

  mock_data "aws_partition" {
    defaults = {
      partition = "aws"
    }
  }

  mock_data "aws_caller_identity" {
    defaults = {
      account_id = "123456789012"
    }
  }

  mock_data "aws_ami" {
    defaults = {
      id = "ami-0123456789abcdef0"
    }
  }

  mock_data "aws_eip" {
    defaults = {
      public_ip = "203.0.113.10"
    }
  }

  mock_data "aws_iam_policy_document" {
    defaults = {
      json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}"
    }
  }

  mock_resource "aws_eip" {
    defaults = {
      id        = "eipalloc-0module0000000000"
      public_ip = "198.51.100.7"
    }
  }

  mock_resource "aws_network_interface" {
    defaults = {
      id = "eni-0static000000000000"
    }
  }

  mock_resource "aws_nat_gateway" {
    defaults = {
      id = "nat-0managed00000000000"
    }
  }
}

variables {
  name                 = "nat-test"
  cidr_block           = "10.10.0.0/16"
  availability_zones   = ["ap-southeast-1a", "ap-southeast-1b", "ap-southeast-1c"]
  public_subnet_cidrs  = ["10.10.0.0/22", "10.10.4.0/22", "10.10.8.0/22"]
  private_subnet_cidrs = ["10.10.16.0/22", "10.10.20.0/22", "10.10.24.0/22"]
}

run "default_is_the_managed_nat_gateway_unchanged" {
  command = plan

  assert {
    condition     = length(aws_eip.nat) == 1 && length(aws_nat_gateway.this) == 1
    error_message = "The default must keep one module-owned EIP and one managed NAT gateway."
  }

  assert {
    condition     = aws_nat_gateway.this[0].allocation_id == aws_eip.nat[0].id && aws_nat_gateway.this[0].subnet_id == aws_subnet.public[0].id
    error_message = "The NAT gateway must keep the module EIP and the first public subnet."
  }

  assert {
    condition     = alltrue([for r in aws_route.private_default : r.nat_gateway_id == aws_nat_gateway.this[0].id])
    error_message = "Every private default route must still target the NAT gateway."
  }

  assert {
    condition = (
      length(aws_network_interface.nat) == 0 &&
      length(aws_launch_template.nat) == 0 &&
      length(aws_autoscaling_group.nat) == 0 &&
      length(aws_security_group.nat_instance) == 0 &&
      length(aws_iam_role.nat_instance) == 0 &&
      length(data.aws_ami.fck_nat) == 0
    )
    error_message = "The default must create no NAT instance resources."
  }

  assert {
    condition     = tolist(output.nat_gateway_public_ips) == tolist([aws_eip.nat[0].public_ip])
    error_message = "nat_gateway_public_ips must still be the module EIP's address."
  }
}

run "gateway_per_az" {
  command = plan

  variables {
    single_nat_gateway = false
  }

  assert {
    condition = (
      length(aws_nat_gateway.this) == 3 &&
      alltrue([for i, r in aws_route.private_default : r.nat_gateway_id == aws_nat_gateway.this[i].id])
    )
    error_message = "single_nat_gateway = false must keep one NAT gateway per AZ, each private route to its own."
  }
}

run "instance_mode_keeps_the_eip_and_routes_to_a_static_eni" {
  command = plan

  variables {
    nat_mode = "instance"
  }

  assert {
    condition     = length(aws_nat_gateway.this) == 0
    error_message = "Instance mode must not create a managed NAT gateway."
  }

  assert {
    condition     = length(aws_eip.nat) == 1 && tolist(output.nat_gateway_public_ips) == tolist([aws_eip.nat[0].public_ip])
    error_message = "Instance mode must keep the module-owned EIP at the same address, so the NAT public IP does not change."
  }

  assert {
    condition     = length(aws_subnet.public) == 3 && length(aws_subnet.private) == 3 && length(aws_route_table.private) == 3
    error_message = "Instance mode must not change the subnet or route table topology."
  }

  assert {
    condition     = alltrue([for r in aws_route.private_default : r.network_interface_id == aws_network_interface.nat[0].id])
    error_message = "Every private default route must target the static NAT ENI."
  }

  assert {
    condition = (
      length(aws_network_interface.nat) == 1 &&
      aws_network_interface.nat[0].source_dest_check == false &&
      aws_network_interface.nat[0].subnet_id == aws_subnet.public[0].id
    )
    error_message = "The static ENI must sit in the first public subnet with source/dest check off."
  }

  assert {
    condition = (
      length(aws_autoscaling_group.nat) == 1 &&
      aws_autoscaling_group.nat[0].min_size == 1 &&
      aws_autoscaling_group.nat[0].max_size == 1 &&
      aws_autoscaling_group.nat[0].desired_capacity == 1 &&
      aws_autoscaling_group.nat[0].vpc_zone_identifier == toset([aws_subnet.public[0].id])
    )
    error_message = "The NAT must run as an Auto Scaling group of exactly one, in the static ENI's subnet."
  }

  assert {
    condition = (
      aws_launch_template.nat[0].instance_type == "t4g.nano" &&
      aws_launch_template.nat[0].image_id == "ami-0123456789abcdef0" &&
      one(aws_launch_template.nat[0].metadata_options).http_tokens == "required" &&
      one(aws_launch_template.nat[0].metadata_options).http_put_response_hop_limit == 1
    )
    error_message = "The launch template must run the resolved fck-nat AMI on t4g.nano with IMDSv2 required."
  }

  assert {
    condition = (
      one(one(aws_launch_template.nat[0].block_device_mappings).ebs).volume_type == "gp3" &&
      one(one(aws_launch_template.nat[0].block_device_mappings).ebs).volume_size == 8 &&
      one(one(aws_launch_template.nat[0].block_device_mappings).ebs).encrypted == "true"
    )
    error_message = "The root volume must be 8 GiB of encrypted gp3."
  }

  assert {
    condition = (
      strcontains(base64decode(aws_launch_template.nat[0].user_data), "eni_id=${aws_network_interface.nat[0].id}") &&
      strcontains(base64decode(aws_launch_template.nat[0].user_data), "eip_id=${aws_eip.nat[0].id}")
    )
    error_message = "User data must configure fck-nat with the static ENI and the module-owned EIP."
  }

  assert {
    condition = (
      one(aws_vpc_security_group_ingress_rule.nat_instance_from_vpc).cidr_ipv4 == "10.10.0.0/16" &&
      one(aws_vpc_security_group_egress_rule.nat_instance_all).cidr_ipv4 == "0.0.0.0/0"
    )
    error_message = "The NAT security group must accept the VPC CIDR and send anywhere."
  }

  assert {
    condition     = one(aws_iam_role_policy_attachment.nat_instance_ssm).policy_arn == "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
    error_message = "The NAT instance must be reachable through Session Manager."
  }

  assert {
    condition     = length(data.aws_ami.fck_nat[0].owners) == 1 && contains(data.aws_ami.fck_nat[0].owners, "568608671756")
    error_message = "The fck-nat AMI must be resolved from the fck-nat publisher only."
  }

  assert {
    condition     = tolist(output.nat_instance_network_interface_ids) == tolist([aws_network_interface.nat[0].id]) && length(output.nat_gateway_ids) == 0
    error_message = "Outputs must report the static ENI and no NAT gateway."
  }
}

run "instance_mode_per_az" {
  command = plan

  variables {
    nat_mode           = "instance"
    single_nat_gateway = false
  }

  assert {
    condition = (
      length(aws_eip.nat) == 3 &&
      length(aws_network_interface.nat) == 3 &&
      length(aws_autoscaling_group.nat) == 3 &&
      alltrue([for i, r in aws_route.private_default : r.network_interface_id == aws_network_interface.nat[i].id]) &&
      alltrue([for i, a in aws_autoscaling_group.nat : a.vpc_zone_identifier == toset([aws_subnet.public[i].id])])
    )
    error_message = "Per-AZ instance mode must run one NAT per AZ, each private route to its own AZ's ENI."
  }
}

run "instance_mode_with_a_pinned_ami_skips_the_lookup" {
  command = plan

  variables {
    nat_mode            = "instance"
    nat_instance_ami_id = "ami-0fedcba9876543210"
  }

  assert {
    condition     = length(data.aws_ami.fck_nat) == 0 && aws_launch_template.nat[0].image_id == "ami-0fedcba9876543210"
    error_message = "nat_instance_ami_id must pin the image and skip the name lookup."
  }
}

run "caller_owned_eip" {
  command = plan

  variables {
    nat_mode               = "instance"
    nat_eip_allocation_ids = ["eipalloc-0caller000000000"]
  }

  assert {
    condition     = length(aws_eip.nat) == 0
    error_message = "With nat_eip_allocation_ids the module must create no EIP of its own."
  }

  assert {
    condition = (
      strcontains(base64decode(aws_launch_template.nat[0].user_data), "eip_id=eipalloc-0caller000000000") &&
      tolist(output.nat_eip_allocation_ids) == tolist(["eipalloc-0caller000000000"]) &&
      tolist(output.nat_gateway_public_ips) == tolist(["203.0.113.10"])
    )
    error_message = "The caller's allocation must reach fck-nat, and its address the output."
  }
}

run "caller_owned_eip_on_a_gateway" {
  command = plan

  variables {
    nat_eip_allocation_ids = ["eipalloc-0caller000000000"]
  }

  assert {
    condition     = length(aws_eip.nat) == 0 && aws_nat_gateway.this[0].allocation_id == "eipalloc-0caller000000000"
    error_message = "The managed NAT gateway must also accept a caller-owned EIP."
  }
}

run "rejects_an_unknown_mode" {
  command = plan

  variables {
    nat_mode = "nat-instance"
  }

  expect_failures = [var.nat_mode]
}

run "rejects_an_x86_instance_type" {
  command = plan

  variables {
    nat_mode          = "instance"
    nat_instance_type = "t3.nano"
  }

  expect_failures = [var.nat_instance_type]
}

run "rejects_the_wrong_number_of_allocations" {
  command = plan

  variables {
    single_nat_gateway     = false
    nat_eip_allocation_ids = ["eipalloc-0caller000000000"]
  }

  expect_failures = [var.nat_eip_allocation_ids]
}

run "rejects_an_address_instead_of_an_allocation" {
  command = plan

  variables {
    nat_eip_allocation_ids = ["192.0.2.1"]
  }

  expect_failures = [var.nat_eip_allocation_ids]
}
