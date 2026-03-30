# Bootstrap: Creates S3 bucket for Terraform state and DynamoDB table for locking
# Run this ONCE before using the main infra module:
#   cd infra/bootstrap && terraform init && terraform apply

terraform {
  required_version = ">= 1.5"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

data "aws_caller_identity" "current" {}

# S3 bucket for Terraform state
resource "aws_s3_bucket" "tf_state" {
  bucket        = "alex-terraform-state-${data.aws_caller_identity.current.account_id}"
  force_destroy = false

  tags = {
    Project     = "alex"
    ManagedBy   = "terraform-bootstrap"
    Description = "Terraform remote state for Alex project"
  }
}

resource "aws_s3_bucket_versioning" "tf_state" {
  bucket = aws_s3_bucket.tf_state.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "tf_state" {
  bucket = aws_s3_bucket.tf_state.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "tf_state" {
  bucket                  = aws_s3_bucket.tf_state.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# DynamoDB table for state locking
resource "aws_dynamodb_table" "tf_locks" {
  name         = "alex-terraform-locks"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "LockID"

  attribute {
    name = "LockID"
    type = "S"
  }

  tags = {
    Project     = "alex"
    ManagedBy   = "terraform-bootstrap"
    Description = "Terraform state locking for Alex project"
  }
}

# IAM group and permissions for CI/CD (Guide 1)
resource "aws_iam_group" "alex_cicd" {
  name = "AlexCICD"
}

resource "aws_iam_group_policy_attachment" "cicd_policies" {
  for_each = toset([
    "arn:aws:iam::aws:policy/AmazonS3FullAccess",
    "arn:aws:iam::aws:policy/AmazonDynamoDBFullAccess",
    "arn:aws:iam::aws:policy/AWSLambda_FullAccess",
    "arn:aws:iam::aws:policy/AmazonRDSFullAccess",
    "arn:aws:iam::aws:policy/AmazonSQSFullAccess",
    "arn:aws:iam::aws:policy/CloudFrontFullAccess",
    "arn:aws:iam::aws:policy/AmazonAPIGatewayAdministrator",
    "arn:aws:iam::aws:policy/IAMFullAccess",
    "arn:aws:iam::aws:policy/AmazonSageMakerFullAccess",
    "arn:aws:iam::aws:policy/SecretsManagerReadWrite",
    "arn:aws:iam::aws:policy/CloudWatchFullAccess",
    "arn:aws:iam::aws:policy/AWSAppRunnerFullAccess",
    "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryFullAccess",
  ])
  group      = aws_iam_group.alex_cicd.name
  policy_arn = each.value
}

output "state_bucket" {
  value       = aws_s3_bucket.tf_state.bucket
  description = "S3 bucket for Terraform state"
}

output "lock_table" {
  value       = aws_dynamodb_table.tf_locks.name
  description = "DynamoDB table for state locking"
}

output "next_steps" {
  value = <<-EOT
    Bootstrap complete!

    State bucket : ${aws_s3_bucket.tf_state.bucket}
    Lock table   : ${aws_dynamodb_table.tf_locks.name}
    Region       : ${var.aws_region}

    Now deploy an environment:
      cd ../
      terraform init \
        -backend-config="bucket=${aws_s3_bucket.tf_state.bucket}" \
        -backend-config="key=dev/terraform.tfstate" \
        -backend-config="region=${var.aws_region}" \
        -backend-config="dynamodb_table=${aws_dynamodb_table.tf_locks.name}"
      terraform apply -var-file="environments/dev.tfvars"
  EOT
}
