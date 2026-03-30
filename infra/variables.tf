# ============================================================
# Core
# ============================================================
variable "aws_region" {
  description = "Primary AWS region"
  type        = string
  default     = "us-east-1"
}

variable "bedrock_region" {
  description = "AWS region where Bedrock models are deployed"
  type        = string
  default     = "us-west-2"
}

variable "project" {
  description = "Project name prefix for all resources"
  type        = string
  default     = "alex"
}

variable "environment" {
  description = "Deployment environment: dev | test | prod"
  type        = string
  validation {
    condition     = contains(["dev", "test", "prod"], var.environment)
    error_message = "environment must be dev, test, or prod"
  }
}

# ============================================================
# SageMaker (Guide 2)
# ============================================================
variable "sagemaker_image_uri" {
  description = "HuggingFace SageMaker container image URI"
  type        = string
  default     = "763104351884.dkr.ecr.us-east-1.amazonaws.com/huggingface-pytorch-inference:1.13.1-transformers4.26.0-cpu-py39-ubuntu20.04"
}

variable "embedding_model_name" {
  description = "HuggingFace model ID for embeddings"
  type        = string
  default     = "sentence-transformers/all-MiniLM-L6-v2"
}

# ============================================================
# Ingestion / Researcher (Guides 3 & 4)
# ============================================================
variable "openai_api_key" {
  description = "OpenAI API key (for Researcher agent and LangFuse tracing)"
  type        = string
  sensitive   = true
}

variable "scheduler_enabled" {
  description = "Enable EventBridge scheduler for the Researcher agent"
  type        = bool
  default     = false
}

# ============================================================
# Database (Guide 5)
# ============================================================
variable "aurora_min_capacity" {
  description = "Aurora Serverless v2 minimum ACUs"
  type        = number
  default     = 0.5
}

variable "aurora_max_capacity" {
  description = "Aurora Serverless v2 maximum ACUs"
  type        = number
  default     = 1.0
}

# ============================================================
# Agents (Guide 6)
# ============================================================
variable "bedrock_model_id" {
  description = "Bedrock model ID (inference profile)"
  type        = string
  default     = "us.amazon.nova-pro-v1:0"
}

variable "polygon_api_key" {
  description = "Polygon.io API key for real-time market data"
  type        = string
  sensitive   = true
}

variable "polygon_plan" {
  description = "Polygon.io plan tier: free | paid"
  type        = string
  default     = "free"
}

variable "planner_memory" {
  description = "Planner Lambda memory in MB"
  type        = number
  default     = 2048
}

variable "agent_memory" {
  description = "Agent Lambda memory in MB (tagger/reporter/charter/retirement)"
  type        = number
  default     = 1024
}

# ============================================================
# LangFuse Observability (Guide 8)
# ============================================================
variable "langfuse_public_key" {
  description = "LangFuse public key (pk-lf-...)"
  type        = string
  default     = ""
}

variable "langfuse_secret_key" {
  description = "LangFuse secret key (sk-lf-...)"
  type        = string
  sensitive   = true
  default     = ""
}

variable "langfuse_host" {
  description = "LangFuse host URL"
  type        = string
  default     = "https://cloud.langfuse.com"
}

# ============================================================
# Frontend / API (Guide 7)
# ============================================================
variable "clerk_jwks_url" {
  description = "Clerk JWKS endpoint URL for JWT validation"
  type        = string
}

variable "clerk_issuer" {
  description = "Clerk issuer URL"
  type        = string
  default     = ""
}

variable "custom_domain" {
  description = "Custom domain name (optional, e.g. myapp.com)"
  type        = string
  default     = ""
}

variable "acm_certificate_arn" {
  description = "ACM certificate ARN for custom domain (must be in us-east-1)"
  type        = string
  default     = ""
}

# ============================================================
# Monitoring (Guide 8)
# ============================================================
variable "enable_monitoring" {
  description = "Deploy CloudWatch dashboards"
  type        = bool
  default     = true
}

variable "lambda_packages_dir" {
  description = "Path to backend directory containing packaged Lambda zips"
  type        = string
  default     = "../backend"
}
