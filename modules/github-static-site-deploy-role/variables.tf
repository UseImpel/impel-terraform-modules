variable "name" {
  type = string
}
variable "github_repository" {
  type = string
}
variable "github_oidc_ids" {
  type     = object({ owner_id = number, repository_id = number })
  default  = null
  nullable = true
}
variable "deploy_branch" {
  type    = string
  default = "dev"
}
variable "github_environment" {
  type     = string
  default  = null
  nullable = true
}
variable "bucket_arn" {
  type = string
}
variable "distribution_arn" {
  type = string
}
