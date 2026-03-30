locals {
  prefix = "${var.project}-${var.environment}"
  tags   = { Project = var.project, Environment = var.environment, ManagedBy = "terraform" }

  agent_env = {
    AURORA_CLUSTER_ARN  = var.aurora_cluster_arn
    AURORA_SECRET_ARN   = var.aurora_secret_arn
    AURORA_DATABASE     = "alex"
    BEDROCK_MODEL_ID    = var.bedrock_model_id
    BEDROCK_REGION      = var.bedrock_region
    AWS_REGION_NAME     = var.bedrock_region
    LANGFUSE_PUBLIC_KEY = var.langfuse_public_key
    LANGFUSE_SECRET_KEY = var.langfuse_secret_key
    LANGFUSE_HOST       = var.langfuse_host
    OPENAI_API_KEY      = var.openai_api_key
  }
}

# ── SQS ───────────────────────────────────────────────────────────────────────
resource "aws_sqs_queue" "dlq" {
  name                       = "${local.prefix}-analysis-jobs-dlq"
  message_retention_seconds  = 1209600
  tags                       = local.tags
}

resource "aws_sqs_queue" "jobs" {
  name                       = "${local.prefix}-analysis-jobs"
  max_message_size           = 262144
  message_retention_seconds  = 86400
  receive_wait_time_seconds  = 10
  visibility_timeout_seconds = 910

  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.dlq.arn
    maxReceiveCount     = 3
  })

  tags = local.tags
}

# ── IAM ───────────────────────────────────────────────────────────────────────
resource "aws_iam_role" "agents" {
  name = "${local.prefix}-lambda-agents-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{ Action = "sts:AssumeRole", Effect = "Allow", Principal = { Service = "lambda.amazonaws.com" } }]
  })
  tags = local.tags
}

resource "aws_iam_role_policy_attachment" "agents_basic" {
  role       = aws_iam_role.agents.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy" "agents" {
  name = "${local.prefix}-lambda-agents-policy"
  role = aws_iam_role.agents.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"]
        Resource = "arn:aws:logs:*:${var.account_id}:*"
      },
      {
        Effect   = "Allow"
        Action   = ["sqs:ReceiveMessage", "sqs:DeleteMessage", "sqs:GetQueueAttributes"]
        Resource = aws_sqs_queue.jobs.arn
      },
      {
        Effect   = "Allow"
        Action   = ["lambda:InvokeFunction"]
        Resource = "arn:aws:lambda:*:${var.account_id}:function:${local.prefix}-*"
      },
      {
        Effect = "Allow"
        Action = [
          "rds-data:ExecuteStatement", "rds-data:BatchExecuteStatement",
          "rds-data:BeginTransaction", "rds-data:CommitTransaction", "rds-data:RollbackTransaction"
        ]
        Resource = var.aurora_cluster_arn
      },
      {
        Effect   = "Allow"
        Action   = ["secretsmanager:GetSecretValue"]
        Resource = var.aurora_secret_arn
      },
      {
        Effect   = "Allow"
        Action   = ["s3:GetObject", "s3:PutObject", "s3:ListBucket"]
        Resource = ["arn:aws:s3:::${var.vector_bucket}", "arn:aws:s3:::${var.vector_bucket}/*"]
      },
      {
        Effect   = "Allow"
        Action   = ["s3vectors:QueryVectors", "s3vectors:GetVectors"]
        Resource = "arn:aws:s3vectors:${var.aws_region}:${var.account_id}:bucket/${var.vector_bucket}/index/*"
      },
      {
        Effect   = "Allow"
        Action   = ["sagemaker:InvokeEndpoint"]
        Resource = "arn:aws:sagemaker:${var.aws_region}:${var.account_id}:endpoint/${var.sagemaker_endpoint}"
      },
      {
        Effect   = "Allow"
        Action   = ["bedrock:InvokeModel", "bedrock:InvokeModelWithResponseStream"]
        Resource = [
          "arn:aws:bedrock:*::foundation-model/*",
          "arn:aws:bedrock:*:${var.account_id}:inference-profile/*"
        ]
      }
    ]
  })
}

# ── S3 bucket for Lambda packages ─────────────────────────────────────────────
resource "aws_s3_bucket" "packages" {
  bucket        = "${local.prefix}-lambda-packages-${var.account_id}"
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

# ── Upload Lambda packages to S3 ──────────────────────────────────────────────
locals {
  agents = ["planner", "tagger", "reporter", "charter", "retirement"]
}

resource "aws_s3_object" "packages" {
  for_each = {
    for a in local.agents : a => "${var.lambda_packages_dir}/${a}/${a}_lambda.zip"
    if fileexists("${var.lambda_packages_dir}/${a}/${a}_lambda.zip")
  }

  bucket = aws_s3_bucket.packages.id
  key    = "${each.key}/${each.key}_lambda.zip"
  source = each.value
  etag   = filemd5(each.value)
}

# ── Lambda Functions ───────────────────────────────────────────────────────────
resource "aws_lambda_function" "planner" {
  function_name = "${local.prefix}-planner"
  role          = aws_iam_role.agents.arn
  s3_bucket     = aws_s3_bucket.packages.id
  s3_key        = "planner/planner_lambda.zip"
  s3_object_version = try(aws_s3_object.packages["planner"].version_id, null)
  handler       = "lambda_handler.lambda_handler"
  runtime       = "python3.12"
  timeout       = 900
  memory_size   = var.planner_memory

  environment {
    variables = merge(local.agent_env, {
      SAGEMAKER_ENDPOINT  = var.sagemaker_endpoint
      VECTOR_BUCKET       = var.vector_bucket
      SQS_QUEUE_URL       = aws_sqs_queue.jobs.url
      POLYGON_API_KEY     = var.polygon_api_key
      POLYGON_PLAN        = var.polygon_plan
    })
  }

  depends_on = [aws_s3_object.packages]
  tags       = local.tags
}

resource "aws_lambda_function" "tagger" {
  function_name     = "${local.prefix}-tagger"
  role              = aws_iam_role.agents.arn
  s3_bucket         = aws_s3_bucket.packages.id
  s3_key            = "tagger/tagger_lambda.zip"
  s3_object_version = try(aws_s3_object.packages["tagger"].version_id, null)
  handler           = "lambda_handler.lambda_handler"
  runtime           = "python3.12"
  timeout           = 300
  memory_size       = var.agent_memory

  environment { variables = local.agent_env }

  depends_on = [aws_s3_object.packages]
  tags       = local.tags
}

resource "aws_lambda_function" "reporter" {
  function_name     = "${local.prefix}-reporter"
  role              = aws_iam_role.agents.arn
  s3_bucket         = aws_s3_bucket.packages.id
  s3_key            = "reporter/reporter_lambda.zip"
  s3_object_version = try(aws_s3_object.packages["reporter"].version_id, null)
  handler           = "lambda_handler.lambda_handler"
  runtime           = "python3.12"
  timeout           = 300
  memory_size       = var.agent_memory

  environment {
    variables = merge(local.agent_env, { SAGEMAKER_ENDPOINT = var.sagemaker_endpoint })
  }

  depends_on = [aws_s3_object.packages]
  tags       = local.tags
}

resource "aws_lambda_function" "charter" {
  function_name     = "${local.prefix}-charter"
  role              = aws_iam_role.agents.arn
  s3_bucket         = aws_s3_bucket.packages.id
  s3_key            = "charter/charter_lambda.zip"
  s3_object_version = try(aws_s3_object.packages["charter"].version_id, null)
  handler           = "lambda_handler.lambda_handler"
  runtime           = "python3.12"
  timeout           = 300
  memory_size       = var.agent_memory

  environment { variables = local.agent_env }

  depends_on = [aws_s3_object.packages]
  tags       = local.tags
}

resource "aws_lambda_function" "retirement" {
  function_name     = "${local.prefix}-retirement"
  role              = aws_iam_role.agents.arn
  s3_bucket         = aws_s3_bucket.packages.id
  s3_key            = "retirement/retirement_lambda.zip"
  s3_object_version = try(aws_s3_object.packages["retirement"].version_id, null)
  handler           = "lambda_handler.lambda_handler"
  runtime           = "python3.12"
  timeout           = 300
  memory_size       = var.agent_memory

  environment { variables = local.agent_env }

  depends_on = [aws_s3_object.packages]
  tags       = local.tags
}

# ── SQS → Planner trigger ─────────────────────────────────────────────────────
resource "aws_lambda_event_source_mapping" "planner_sqs" {
  event_source_arn = aws_sqs_queue.jobs.arn
  function_name    = aws_lambda_function.planner.arn
  batch_size       = 1
}

# ── CloudWatch log groups ─────────────────────────────────────────────────────
resource "aws_cloudwatch_log_group" "agents" {
  for_each          = toset(local.agents)
  name              = "/aws/lambda/${local.prefix}-${each.key}"
  retention_in_days = 7
  tags              = local.tags
}
