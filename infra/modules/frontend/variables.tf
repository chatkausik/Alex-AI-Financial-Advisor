variable "project"            { type = string }
variable "environment"        { type = string }
variable "aws_region"         { type = string }
variable "account_id"         { type = string }
variable "aurora_cluster_arn" { type = string }
variable "aurora_secret_arn"  { type = string }
variable "sqs_queue_url"      { type = string }
variable "clerk_jwks_url"     { type = string }
variable "lambda_packages_dir" { type = string }

variable "clerk_issuer" {
  type    = string
  default = ""
}

variable "custom_domain" {
  type    = string
  default = ""
}

variable "acm_certificate_arn" {
  type    = string
  default = ""
}
