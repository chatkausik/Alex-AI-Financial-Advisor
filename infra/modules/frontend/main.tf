locals {
  prefix      = "${var.project}-${var.environment}"
  tags        = { Project = var.project, Environment = var.environment, ManagedBy = "terraform" }
  api_zip     = "${var.lambda_packages_dir}/api/api_lambda.zip"
  has_domain  = var.custom_domain != "" && var.acm_certificate_arn != ""
  cf_aliases  = local.has_domain ? [var.custom_domain, "www.${var.custom_domain}"] : []
}

# ── S3 Bucket for API Lambda package ──────────────────────────────────────────
resource "aws_s3_bucket" "packages" {
  bucket        = "${local.prefix}-api-packages-${var.account_id}"
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

resource "aws_s3_object" "api_package" {
  count  = fileexists(local.api_zip) ? 1 : 0
  bucket = aws_s3_bucket.packages.id
  key    = "api/api_lambda.zip"
  source = local.api_zip
  etag   = fileexists(local.api_zip) ? filemd5(local.api_zip) : null
}

# ── S3 Static Site (private — served via CloudFront OAC) ──────────────────────
resource "aws_s3_bucket" "frontend" {
  bucket        = "${local.prefix}-frontend-${var.account_id}"
  force_destroy = true
  tags          = local.tags
}

resource "aws_s3_bucket_public_access_block" "frontend" {
  bucket                  = aws_s3_bucket.frontend.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# ── CloudFront Origin Access Control ──────────────────────────────────────────
resource "aws_cloudfront_origin_access_control" "frontend" {
  name                              = "${local.prefix}-oac"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

# Bucket policy: allow only CloudFront OAC to read objects
resource "aws_s3_bucket_policy" "frontend" {
  bucket = aws_s3_bucket.frontend.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "cloudfront.amazonaws.com" }
      Action    = "s3:GetObject"
      Resource  = "${aws_s3_bucket.frontend.arn}/*"
      Condition = {
        StringEquals = {
          "AWS:SourceArn" = aws_cloudfront_distribution.main.arn
        }
      }
    }]
  })
  depends_on = [aws_cloudfront_distribution.main]
}

# ── API Lambda ────────────────────────────────────────────────────────────────
resource "aws_iam_role" "api" {
  name = "${local.prefix}-api-lambda-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{ Action = "sts:AssumeRole", Effect = "Allow", Principal = { Service = "lambda.amazonaws.com" } }]
  })
  tags = local.tags
}

resource "aws_iam_role_policy_attachment" "api_basic" {
  role       = aws_iam_role.api.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy" "api_aurora" {
  name = "${local.prefix}-api-aurora"
  role = aws_iam_role.api.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["rds-data:ExecuteStatement", "rds-data:BatchExecuteStatement", "rds-data:BeginTransaction", "rds-data:CommitTransaction", "rds-data:RollbackTransaction"]
        Resource = var.aurora_cluster_arn
      },
      {
        Effect   = "Allow"
        Action   = ["secretsmanager:GetSecretValue"]
        Resource = var.aurora_secret_arn
      },
      {
        Effect   = "Allow"
        Action   = ["sqs:SendMessage"]
        Resource = "arn:aws:sqs:${var.aws_region}:${var.account_id}:${local.prefix}-analysis-jobs"
      },
      {
        Effect   = "Allow"
        Action   = ["lambda:InvokeFunction"]
        Resource = "arn:aws:lambda:${var.aws_region}:${var.account_id}:function:${local.prefix}-*"
      }
    ]
  })
}

resource "aws_lambda_function" "api" {
  function_name     = "${local.prefix}-api"
  role              = aws_iam_role.api.arn
  s3_bucket         = aws_s3_bucket.packages.id
  s3_key            = "api/api_lambda.zip"
  s3_object_version = try(aws_s3_object.api_package[0].version_id, null)
  handler           = "lambda_handler.handler"
  runtime           = "python3.12"
  timeout           = 30
  memory_size       = 512

  depends_on = [aws_s3_object.api_package]

  environment {
    variables = {
      AURORA_CLUSTER_ARN = var.aurora_cluster_arn
      AURORA_SECRET_ARN  = var.aurora_secret_arn
      AURORA_DATABASE    = "alex"
      SQS_QUEUE_URL      = var.sqs_queue_url
      CLERK_JWKS_URL     = var.clerk_jwks_url
      CLERK_ISSUER       = var.clerk_issuer
      DEFAULT_AWS_REGION = var.aws_region
      CORS_ORIGINS       = local.has_domain ? "http://localhost:3000,https://${local.prefix}-frontend.s3-website-${var.aws_region}.amazonaws.com,https://${var.custom_domain},https://www.${var.custom_domain}" : "http://localhost:3000"
    }
  }

  tags = local.tags
}

resource "aws_cloudwatch_log_group" "api" {
  name              = "/aws/lambda/${local.prefix}-api"
  retention_in_days = 7
  tags              = local.tags
}

# ── API Gateway HTTP ──────────────────────────────────────────────────────────
resource "aws_apigatewayv2_api" "main" {
  name          = "${local.prefix}-api-gateway"
  protocol_type = "HTTP"

  cors_configuration {
    allow_headers = ["content-type", "authorization", "x-amz-date", "x-api-key"]
    allow_methods = ["GET", "POST", "PUT", "DELETE", "OPTIONS"]
    allow_origins = local.has_domain ? [
      "http://localhost:3000",
      "https://${var.custom_domain}",
      "https://www.${var.custom_domain}"
    ] : ["*"]
    max_age = 300
  }

  tags = local.tags
}

resource "aws_apigatewayv2_stage" "default" {
  api_id      = aws_apigatewayv2_api.main.id
  name        = "$default"
  auto_deploy = true

  default_route_settings {
    throttling_rate_limit  = 100
    throttling_burst_limit = 100
  }

  tags = local.tags
}

resource "aws_apigatewayv2_integration" "lambda" {
  api_id                 = aws_apigatewayv2_api.main.id
  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_function.api.invoke_arn
  payload_format_version = "2.0"
}

resource "aws_apigatewayv2_route" "api" {
  api_id    = aws_apigatewayv2_api.main.id
  route_key = "ANY /api/{proxy+}"
  target    = "integrations/${aws_apigatewayv2_integration.lambda.id}"
}

resource "aws_apigatewayv2_route" "options" {
  api_id    = aws_apigatewayv2_api.main.id
  route_key = "OPTIONS /api/{proxy+}"
  target    = "integrations/${aws_apigatewayv2_integration.lambda.id}"
}

resource "aws_lambda_permission" "apigw" {
  statement_id  = "AllowExecutionFromAPIGateway"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.api.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.main.execution_arn}/*/*"
}

# ── CloudFront ────────────────────────────────────────────────────────────────
resource "aws_cloudfront_distribution" "main" {
  enabled             = true
  is_ipv6_enabled     = true
  default_root_object = "index.html"
  aliases             = local.cf_aliases

  origin {
    origin_id                = "S3-${aws_s3_bucket.frontend.id}"
    domain_name              = aws_s3_bucket.frontend.bucket_regional_domain_name
    origin_access_control_id = aws_cloudfront_origin_access_control.frontend.id
  }

  origin {
    origin_id   = "APIGateway"
    domain_name = replace(aws_apigatewayv2_api.main.api_endpoint, "https://", "")

    custom_origin_config {
      http_port              = 80
      https_port             = 443
      origin_protocol_policy = "https-only"
      origin_ssl_protocols   = ["TLSv1.2"]
    }
  }

  default_cache_behavior {
    target_origin_id       = "S3-${aws_s3_bucket.frontend.id}"
    viewer_protocol_policy = "redirect-to-https"
    allowed_methods        = ["GET", "HEAD"]
    cached_methods         = ["GET", "HEAD"]
    compress               = true

    forwarded_values {
      query_string = false
      cookies { forward = "none" }
    }

    min_ttl     = 0
    default_ttl = 86400
    max_ttl     = 31536000
  }

  ordered_cache_behavior {
    path_pattern           = "/api/*"
    target_origin_id       = "APIGateway"
    viewer_protocol_policy = "redirect-to-https"
    allowed_methods        = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
    cached_methods         = ["GET", "HEAD"]
    compress               = true

    forwarded_values {
      query_string = true
      headers      = ["Authorization", "Content-Type"]
      cookies { forward = "none" }
    }

    min_ttl     = 0
    default_ttl = 0
    max_ttl     = 0
  }

  custom_error_response {
    error_code            = 404
    response_code         = 200
    response_page_path    = "/index.html"
    error_caching_min_ttl = 0
  }

  custom_error_response {
    error_code            = 403
    response_code         = 200
    response_page_path    = "/index.html"
    error_caching_min_ttl = 0
  }

  viewer_certificate {
    acm_certificate_arn            = local.has_domain ? var.acm_certificate_arn : null
    ssl_support_method             = local.has_domain ? "sni-only" : null
    minimum_protocol_version       = local.has_domain ? "TLSv1.2_2021" : "TLSv1"
    cloudfront_default_certificate = !local.has_domain
  }

  restrictions {
    geo_restriction { restriction_type = "none" }
  }

  tags = local.tags
}

# ── Update API Lambda CORS with CloudFront URL ────────────────────────────────
resource "aws_lambda_function_event_invoke_config" "api_cors" {
  function_name = aws_lambda_function.api.function_name
  depends_on    = [aws_cloudfront_distribution.main]

  lifecycle {
    ignore_changes = all
  }
}
