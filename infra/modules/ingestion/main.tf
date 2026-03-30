locals {
  prefix = "${var.project}-${var.environment}"
  tags   = { Project = var.project, Environment = var.environment, ManagedBy = "terraform" }
}

# ── S3 Vectors Bucket ─────────────────────────────────────────────────────────
resource "aws_s3_bucket" "vectors" {
  bucket = "${local.prefix}-vectors-${var.account_id}"
  tags   = local.tags
}

resource "aws_s3_bucket_versioning" "vectors" {
  bucket = aws_s3_bucket.vectors.id
  versioning_configuration { status = "Enabled" }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "vectors" {
  bucket = aws_s3_bucket.vectors.id
  rule {
    apply_server_side_encryption_by_default { sse_algorithm = "AES256" }
  }
}

resource "aws_s3_bucket_public_access_block" "vectors" {
  bucket                  = aws_s3_bucket.vectors.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# ── S3 Bucket for Lambda package ──────────────────────────────────────────────
resource "aws_s3_bucket" "packages" {
  bucket        = "${local.prefix}-ingest-packages-${var.account_id}"
  force_destroy = true
  tags          = local.tags
}

resource "aws_s3_bucket_public_access_block" "packages" {
  bucket                  = aws_s3_bucket.packages.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

locals {
  ingest_zip = "${var.lambda_packages_dir}/ingest/lambda_function.zip"
}

resource "aws_s3_object" "ingest_package" {
  count  = fileexists(local.ingest_zip) ? 1 : 0
  bucket = aws_s3_bucket.packages.id
  key    = "ingest/lambda_function.zip"
  source = local.ingest_zip
  etag   = fileexists(local.ingest_zip) ? filemd5(local.ingest_zip) : null
}

# ── Lambda Ingest ─────────────────────────────────────────────────────────────
resource "aws_iam_role" "ingest_lambda" {
  name = "${local.prefix}-ingest-lambda-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{ Action = "sts:AssumeRole", Effect = "Allow", Principal = { Service = "lambda.amazonaws.com" } }]
  })
  tags = local.tags
}

resource "aws_iam_role_policy" "ingest_lambda" {
  name = "${local.prefix}-ingest-lambda-policy"
  role = aws_iam_role.ingest_lambda.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"]
        Resource = "arn:aws:logs:${var.aws_region}:${var.account_id}:*"
      },
      {
        Effect   = "Allow"
        Action   = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject", "s3:ListBucket"]
        Resource = [aws_s3_bucket.vectors.arn, "${aws_s3_bucket.vectors.arn}/*"]
      },
      {
        Effect   = "Allow"
        Action   = ["sagemaker:InvokeEndpoint"]
        Resource = "arn:aws:sagemaker:${var.aws_region}:${var.account_id}:endpoint/${var.sagemaker_endpoint}"
      },
      {
        Effect   = "Allow"
        Action   = ["s3vectors:PutVectors", "s3vectors:QueryVectors", "s3vectors:GetVectors", "s3vectors:DeleteVectors"]
        Resource = "arn:aws:s3vectors:${var.aws_region}:${var.account_id}:bucket/${aws_s3_bucket.vectors.id}/index/*"
      }
    ]
  })
}

resource "aws_lambda_function" "ingest" {
  function_name     = "${local.prefix}-ingest"
  role              = aws_iam_role.ingest_lambda.arn
  s3_bucket         = aws_s3_bucket.packages.id
  s3_key            = "ingest/lambda_function.zip"
  s3_object_version = try(aws_s3_object.ingest_package[0].version_id, null)
  handler           = "ingest_s3vectors.lambda_handler"
  runtime           = "python3.12"
  timeout           = 60
  memory_size       = 512

  environment {
    variables = {
      VECTOR_BUCKET      = aws_s3_bucket.vectors.id
      SAGEMAKER_ENDPOINT = var.sagemaker_endpoint
    }
  }

  depends_on = [aws_s3_object.ingest_package]
  tags       = local.tags
}

resource "aws_cloudwatch_log_group" "ingest" {
  name              = "/aws/lambda/${local.prefix}-ingest"
  retention_in_days = 7
  tags              = local.tags
}

# ── API Gateway (ingest endpoint) ─────────────────────────────────────────────
resource "aws_api_gateway_rest_api" "ingest" {
  name        = "${local.prefix}-ingest-api"
  description = "Alex ingestion API"
  endpoint_configuration { types = ["REGIONAL"] }
  tags = local.tags
}

resource "aws_api_gateway_resource" "ingest" {
  rest_api_id = aws_api_gateway_rest_api.ingest.id
  parent_id   = aws_api_gateway_rest_api.ingest.root_resource_id
  path_part   = "ingest"
}

resource "aws_api_gateway_method" "ingest_post" {
  rest_api_id      = aws_api_gateway_rest_api.ingest.id
  resource_id      = aws_api_gateway_resource.ingest.id
  http_method      = "POST"
  authorization    = "NONE"
  api_key_required = true
}

resource "aws_api_gateway_integration" "ingest" {
  rest_api_id             = aws_api_gateway_rest_api.ingest.id
  resource_id             = aws_api_gateway_resource.ingest.id
  http_method             = aws_api_gateway_method.ingest_post.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.ingest.invoke_arn
}

resource "aws_lambda_permission" "apigw_ingest" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.ingest.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.ingest.execution_arn}/*/*"
}

resource "aws_api_gateway_deployment" "ingest" {
  rest_api_id = aws_api_gateway_rest_api.ingest.id
  triggers = {
    redeployment = sha1(jsonencode([
      aws_api_gateway_resource.ingest.id,
      aws_api_gateway_method.ingest_post.id,
      aws_api_gateway_integration.ingest.id,
    ]))
  }
  lifecycle { create_before_destroy = true }
}

resource "aws_api_gateway_stage" "ingest" {
  deployment_id = aws_api_gateway_deployment.ingest.id
  rest_api_id   = aws_api_gateway_rest_api.ingest.id
  stage_name    = var.environment
  tags          = local.tags
}

resource "aws_api_gateway_api_key" "ingest" {
  name = "${local.prefix}-ingest-api-key"
  tags = local.tags
}

resource "aws_api_gateway_usage_plan" "ingest" {
  name = "${local.prefix}-ingest-usage-plan"
  api_stages {
    api_id = aws_api_gateway_rest_api.ingest.id
    stage  = aws_api_gateway_stage.ingest.stage_name
  }
  quota_settings {
    limit  = 10000
    period = "MONTH"
  }
  throttle_settings {
    rate_limit  = 100
    burst_limit = 200
  }
}

resource "aws_api_gateway_usage_plan_key" "ingest" {
  key_id        = aws_api_gateway_api_key.ingest.id
  key_type      = "API_KEY"
  usage_plan_id = aws_api_gateway_usage_plan.ingest.id
}
