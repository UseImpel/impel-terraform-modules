# alb

Application Load Balancer with the prod SEA listener shape: `:80` redirects to `:443`, `:443`
terminates TLS on `ELBSecurityPolicy-TLS13-1-2-2021-06` and forwards to whatever rules callers
attach.

Prod runs one of these per service, each internet-facing with its own certificate and WAF. Dev runs
a single internal instance and separates services with host-based listener rules created by
[`../ecs-service`](../ecs-service).

## Creates

- `aws_lb` (application type) and its security group
- Ingress rules on `:80` and `:443` from `ingress_cidr_blocks`; open egress so the ALB can reach
  targets on their container ports
- `:80` listener — 301 redirect to HTTPS when a certificate is supplied, fixed response otherwise
- `:443` listener with a **fixed-response default action**, plus any SNI certificates
- Optionally, an access log bucket with public access blocked, versioning, SSE-S3, TLS-only policy
  and a lifecycle expiry

## Call

```hcl
module "alb" {
  source = "../../modules/alb"

  name                = "impel-gateway-${var.environment}"
  vpc_id              = module.vpc.vpc_id
  subnet_ids          = module.vpc.private_subnet_ids
  internal            = true
  certificate_arn     = var.wildcard_certificate_arn
  ingress_cidr_blocks = [module.vpc.vpc_cidr_block]
}
```

Then attach services to `module.alb.listener_arn`.

When the certificate is created in the **same apply** as the load balancer, state `enable_https`
rather than letting the module infer it:

```hcl
module "certificate" {
  source      = "../../modules/acm-certificate"
  domain_name = "*.dev.example.com"
}

module "alb" {
  source = "../../modules/alb"

  certificate_arn = module.certificate.arn
  enable_https    = true
  # ...
}
```

## Notes

**`enable_https` exists because `count` and `for_each` must resolve at plan time.** The `:443`
listener and its ingress rules are conditional on whether the ALB serves HTTPS. Inferring that from
`certificate_arn != null` is correct whenever the ARN is already known — but a certificate created in
the same apply has an unknown ARN, the inference is unknown with it, and the plan fails with
`Invalid for_each argument`. Setting `enable_https` states the answer statically. Leave it null and
the inference applies, which is right for a pre-existing certificate. `../ecs-service` carries
`attach_load_balancer` for the same reason.

Setting `enable_https = true` without a `certificate_arn` fails a precondition rather than creating a
listener AWS would reject.

**The default action is a fixed 404, not a forward.** On a shared ALB, a forward default means any
unmatched host silently reaches whichever service happens to hold the default target group.
Returning `404` makes a missing host rule a visible failure instead of a routing accident.

Use the `listener_arn` output rather than picking between `https_listener_arn` and
`http_listener_arn` — it resolves to whichever listener actually carries rules.

Access log buckets are encrypted with **SSE-S3, not a CMK**. ELB log delivery does not support
customer-managed keys; configuring one makes delivery fail silently, with a healthy load balancer
and no logs.

No WAF association. Prod attaches a regional WebACL per ALB from CDK; that stays a caller decision.
