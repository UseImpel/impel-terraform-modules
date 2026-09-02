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

  # Custom health checks, because ECS itself reports task health to Cloud Map.
  # A threshold of 1 removes a stopped task's record on the first report
  # rather than serving a dead address for extra 30-second intervals. AWS now
  # fixes the threshold at 1 and the provider deprecates the argument — kept
  # explicit, matching what actually happens, until a provider major drops it.
  health_check_custom_config {
    failure_threshold = 1
  }

  tags = {
    Name = each.value
  }
}
