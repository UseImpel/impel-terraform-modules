variable "name" {
  type        = string
  description = "Stable distribution and bucket name prefix."
}

variable "bucket_name" {
  type        = string
  description = "Globally unique private S3 bucket name for the SPA."
}

variable "aliases" {
  type        = list(string)
  description = "CloudFront aliases served by this distribution."
}

variable "certificate_arn" {
  type        = string
  description = "ACM certificate ARN in us-east-1 covering aliases."
}

variable "api_origin_domain_name" {
  type        = string
  description = "HTTPS DNS name of the shared ALB API origin."
}

variable "web_acl_arn" {
  type        = string
  default     = null
  nullable    = true
  description = "Optional WAF web ACL ARN."
}

variable "price_class" {
  type    = string
  default = "PriceClass_100"
}
