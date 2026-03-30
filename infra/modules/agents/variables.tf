variable "project"            { type = string }
variable "environment"        { type = string }
variable "aws_region"         { type = string }
variable "account_id"         { type = string }
variable "aurora_cluster_arn" { type = string }
variable "aurora_secret_arn"  { type = string }
variable "vector_bucket"      { type = string }
variable "bedrock_model_id"   { type = string }
variable "bedrock_region"     { type = string }
variable "sagemaker_endpoint" { type = string }
variable "lambda_packages_dir" { type = string }

variable "polygon_api_key" {
  type      = string
  sensitive = true
}

variable "polygon_plan" {
  type    = string
  default = "free"
}

variable "langfuse_public_key" {
  type    = string
  default = ""
}

variable "langfuse_secret_key" {
  type      = string
  sensitive = true
  default   = ""
}

variable "langfuse_host" {
  type    = string
  default = "https://cloud.langfuse.com"
}

variable "openai_api_key" {
  type      = string
  sensitive = true
  default   = ""
}

variable "planner_memory" {
  type    = number
  default = 2048
}

variable "agent_memory" {
  type    = number
  default = 1024
}
