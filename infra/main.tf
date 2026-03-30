provider "aws" {
  region = var.aws_region
  default_tags {
    tags = {
      Project     = var.project
      Environment = var.environment
      ManagedBy   = "terraform"
    }
  }
}

data "aws_caller_identity" "current" {}

# ── Guide 2: SageMaker Embedding Endpoint ─────────────────────────────────────
module "sagemaker" {
  source = "./modules/sagemaker"

  project              = var.project
  environment          = var.environment
  aws_region           = var.aws_region
  sagemaker_image_uri  = var.sagemaker_image_uri
  embedding_model_name = var.embedding_model_name
}

# ── Guide 3: Ingestion Pipeline & S3 Vectors ──────────────────────────────────
module "ingestion" {
  source = "./modules/ingestion"

  project             = var.project
  environment         = var.environment
  aws_region          = var.aws_region
  account_id          = data.aws_caller_identity.current.account_id
  sagemaker_endpoint  = module.sagemaker.endpoint_name
  lambda_packages_dir = var.lambda_packages_dir

  depends_on = [module.sagemaker]
}

# ── Guide 5: Aurora Serverless v2 Database ────────────────────────────────────
module "database" {
  source = "./modules/database"

  project      = var.project
  environment  = var.environment
  aws_region   = var.aws_region
  account_id   = data.aws_caller_identity.current.account_id
  min_capacity = var.aurora_min_capacity
  max_capacity = var.aurora_max_capacity
}

# ── Guide 6: Multi-Agent Lambda Orchestra ─────────────────────────────────────
module "agents" {
  source = "./modules/agents"

  project             = var.project
  environment         = var.environment
  aws_region          = var.aws_region
  account_id          = data.aws_caller_identity.current.account_id
  aurora_cluster_arn  = module.database.cluster_arn
  aurora_secret_arn   = module.database.secret_arn
  vector_bucket       = module.ingestion.vector_bucket
  bedrock_model_id    = var.bedrock_model_id
  bedrock_region      = var.bedrock_region
  sagemaker_endpoint  = module.sagemaker.endpoint_name
  polygon_api_key     = var.polygon_api_key
  polygon_plan        = var.polygon_plan
  langfuse_public_key = var.langfuse_public_key
  langfuse_secret_key = var.langfuse_secret_key
  langfuse_host       = var.langfuse_host
  openai_api_key      = var.openai_api_key
  planner_memory      = var.planner_memory
  agent_memory        = var.agent_memory
  lambda_packages_dir = var.lambda_packages_dir

  depends_on = [module.database, module.ingestion]
}

# ── Guide 7: Frontend, API Gateway, CloudFront ────────────────────────────────
module "frontend" {
  source = "./modules/frontend"

  project             = var.project
  environment         = var.environment
  aws_region          = var.aws_region
  account_id          = data.aws_caller_identity.current.account_id
  aurora_cluster_arn  = module.database.cluster_arn
  aurora_secret_arn   = module.database.secret_arn
  sqs_queue_url       = module.agents.sqs_queue_url
  clerk_jwks_url      = var.clerk_jwks_url
  clerk_issuer        = var.clerk_issuer
  custom_domain       = var.custom_domain
  acm_certificate_arn = var.acm_certificate_arn
  lambda_packages_dir = var.lambda_packages_dir

  depends_on = [module.database, module.agents]
}

# ── Guide 8: CloudWatch Dashboards & Monitoring ───────────────────────────────
module "monitoring" {
  source = "./modules/monitoring"
  count  = var.enable_monitoring ? 1 : 0

  project          = var.project
  environment      = var.environment
  aws_region       = var.aws_region
  bedrock_region   = var.bedrock_region
  bedrock_model_id = "amazon.nova-pro-v1:0"

  depends_on = [module.agents, module.frontend]
}
