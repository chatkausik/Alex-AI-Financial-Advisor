locals {
  prefix = "${var.project}-${var.environment}"
  tags   = { Project = var.project, Environment = var.environment, ManagedBy = "terraform" }
}

resource "aws_iam_role" "sagemaker" {
  name = "${local.prefix}-sagemaker-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{ Action = "sts:AssumeRole", Effect = "Allow", Principal = { Service = "sagemaker.amazonaws.com" } }]
  })
  tags = local.tags
}

resource "aws_iam_role_policy_attachment" "sagemaker_full_access" {
  role       = aws_iam_role.sagemaker.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSageMakerFullAccess"
}

resource "aws_sagemaker_model" "embedding" {
  name               = "${local.prefix}-embedding-model"
  execution_role_arn = aws_iam_role.sagemaker.arn

  primary_container {
    image = var.sagemaker_image_uri
    environment = {
      HF_MODEL_ID = var.embedding_model_name
      HF_TASK     = "feature-extraction"
    }
  }

  depends_on = [aws_iam_role_policy_attachment.sagemaker_full_access]
  tags       = local.tags
}

resource "aws_sagemaker_endpoint_configuration" "serverless" {
  name = "${local.prefix}-embedding-serverless-config"

  production_variants {
    model_name = aws_sagemaker_model.embedding.name
    serverless_config {
      memory_size_in_mb = 3072
      max_concurrency   = 2
    }
  }

  tags = local.tags
}

resource "time_sleep" "iam_propagation" {
  depends_on      = [aws_iam_role_policy_attachment.sagemaker_full_access]
  create_duration = "15s"
}

resource "aws_sagemaker_endpoint" "embedding" {
  name                 = "${local.prefix}-embedding-endpoint"
  endpoint_config_name = aws_sagemaker_endpoint_configuration.serverless.name
  depends_on           = [time_sleep.iam_propagation]
  tags                 = local.tags
}
