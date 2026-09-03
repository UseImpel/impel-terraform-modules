# One private Cloud Map namespace plus an A-record discovery service per
# entry, giving tasks stable DNS names (<service>.<namespace>) inside the VPC
# with no load balancer in front. ECS registers and deregisters each task's
# ENI address as tasks start and stop.

resource "aws_service_discovery_private_dns_namespace" "this" {
  name        = var.name
  description = var.description
  vpc         = var.vpc_id

  tags = {
    Name = var.name
  }
}

resource "aws_service_discovery_service" "this" {
  for_each = var.services

  name = each.value

  dns_config {
    namespace_id = aws_service_discovery_private_dns_namespace.this.id

    # MULTIVALUE returns every healthy task address and lets the client pick;
    # a low TTL keeps stale ENI addresses from outliving a task by long.
    routing_policy = "MULTIVALUE"

    dns_records {
      type = "A"
      ttl  = 10
    }
  }

  # No health_check_custom_config. An empty block carries only the deprecated
  # failure_threshold, so the API drops it and returns a service without the
  # attribute -- while the config still declares one. That mismatch is
  # replace-forcing and immutable, so every plan proposed replacing the service
  # forever. ECS registers and deregisters task addresses either way.

  tags = {
    Name = each.value
  }
}
