# vpc

Two-tier VPC for ECS Fargate workloads, shaped after the live
`ImpelGatewaySeaFoundation` VPC (`10.90.0.0/16`) documented in
[`docs/prod-sea-mapping.md`](https://github.com/UseImpel/impel-infra-prod/blob/main/docs/prod-sea-mapping.md).

## Creates

- VPC with DNS support and hostnames enabled
- One public and one private subnet per availability zone
- Internet gateway, one shared public route table
- NAT gateway(s) with Elastic IPs — one for the whole VPC by default, matching prod
- Per-subnet private route tables, each defaulting to a NAT gateway
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
