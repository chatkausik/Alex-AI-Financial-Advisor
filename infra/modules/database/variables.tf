variable "project"     { type = string }
variable "environment" { type = string }
variable "aws_region"  { type = string }
variable "account_id"  { type = string }

variable "min_capacity" {
  type    = number
  default = 0.5
}

variable "max_capacity" {
  type    = number
  default = 1.0
}
