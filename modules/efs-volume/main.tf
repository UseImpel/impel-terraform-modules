# One EFS filesystem, encrypted at rest, with a security group scoped to a
# single caller-supplied source and one access point per entry in
# var.access_points. Transit encryption and IAM authorization are mount-time
# settings on the ECS task definition's volume block, not on the filesystem
# itself, so this module has no toggle for either.

resource "aws_efs_file_system" "this" {
  creation_token = var.name
  encrypted      = true
  kms_key_id     = var.kms_key_arn

  tags = {
    Name = var.name
  }
}

resource "aws_security_group" "this" {
  name        = "${var.name}-efs"
  description = "EFS ${var.name} accepts NFS only from allowed_security_group_id."
  vpc_id      = var.vpc_id

  tags = {
    Name = "${var.name}-efs"
  }
}

# Source security group only; there is deliberately no CIDR variable.
resource "aws_vpc_security_group_ingress_rule" "nfs" {
  security_group_id = aws_security_group.this.id
  description       = "NFS from ${var.allowed_security_group_id}."

  referenced_security_group_id = var.allowed_security_group_id
  from_port                    = 2049
  to_port                      = 2049
  ip_protocol                  = "tcp"
}

resource "aws_efs_mount_target" "this" {
  for_each = toset(var.subnet_ids)

  file_system_id  = aws_efs_file_system.this.id
  subnet_id       = each.value
  security_groups = [aws_security_group.this.id]
}

resource "aws_efs_access_point" "this" {
  for_each = var.access_points

  file_system_id = aws_efs_file_system.this.id

  posix_user {
    uid = each.value.uid
    gid = each.value.gid
  }

  root_directory {
    path = each.value.root_directory_path

    creation_info {
      owner_uid   = each.value.uid
      owner_gid   = each.value.gid
      permissions = each.value.permissions
    }
  }

  tags = {
    Name = "${var.name}-${each.key}"
  }
}
