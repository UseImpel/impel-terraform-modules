# private-dns-namespace

One private Cloud Map DNS namespace and an A-record discovery service per entry. Gives tasks
stable names inside the VPC — `query.code-intelligence.internal` — with no load balancer in
front: ECS registers each task's ENI address as it starts and removes it as it stops.

## Creates

- `aws_service_discovery_private_dns_namespace` — visible only to resolvers inside the VPC
- `aws_service_discovery_service` per entry in `services` — A records, TTL 10, `MULTIVALUE`
  routing, custom health checks with `failure_threshold = 1`

## Call

```hcl
module "code_intelligence_dns" {
  source = "../../modules/private-dns-namespace"

  name        = "code-intelligence.internal"
  vpc_id      = module.vpc.vpc_id
  description = "Service discovery for the code intelligence services."

  services = ["api", "query"]
}
```

Then register a service's tasks by passing the matching registry ARN to
[`../ecs-service`](../ecs-service):

```hcl
module "query_service" {
  source = "../../modules/ecs-service"
  # ...
  attach_load_balancer = false
  service_registry_arn = module.code_intelligence_dns.service_registry_arns["query"]
}
```

## Notes

**`MULTIVALUE` with TTL 10.** A lookup returns every healthy task address and the client picks
one; the low TTL keeps a stopped task's address from being served long after the ENI is gone.

**Custom health checks, `failure_threshold = 1`.** ECS itself reports task health to Cloud Map —
there is no Route 53 health checker probing tasks in private subnets, and Cloud Map rejects
Route 53 health checks on a private namespace anyway. The threshold of 1 removes a record on the
first unhealthy report instead of serving a dead address for extra 30-second intervals.

**DNS only, not the boundary.** A resolvable name is not reachability: the target service's task
security group still accepts nothing by default when it has no load balancer. Open the port with
`ecs-service`'s `ingress_security_group_rules` on the callee, naming the caller's task security
group.
