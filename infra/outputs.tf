output "environment" { value = var.environment }

# SageMaker
output "sagemaker_endpoint"   { value = module.sagemaker.endpoint_name }

# Ingestion
output "vector_bucket"        { value = module.ingestion.vector_bucket }
output "ingest_api_endpoint"  { value = module.ingestion.api_endpoint }
output "ingest_api_key"       { value = module.ingestion.api_key_value; sensitive = true }

# Database
output "aurora_cluster_arn"   { value = module.database.cluster_arn }
output "aurora_secret_arn"    { value = module.database.secret_arn }

# Agents
output "sqs_queue_url"        { value = module.agents.sqs_queue_url }

# Frontend
output "cloudfront_url"       { value = module.frontend.cloudfront_url }
output "api_gateway_url"      { value = module.frontend.api_gateway_url }
output "frontend_bucket"      { value = module.frontend.s3_bucket }

output "deployment_summary" {
  value = <<-EOT
    ============================================================
    Alex ${upper(var.environment)} Deployment
    ============================================================
    Frontend   : ${module.frontend.cloudfront_url}
    API        : ${module.frontend.api_gateway_url}
    SQS Queue  : ${module.agents.sqs_queue_url}
    Aurora ARN : ${module.database.cluster_arn}
    ============================================================
  EOT
}
