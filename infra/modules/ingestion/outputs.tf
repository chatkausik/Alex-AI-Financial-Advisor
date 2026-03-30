output "vector_bucket" {
  value = aws_s3_bucket.vectors.id
}

output "api_endpoint" {
  value = "https://${aws_api_gateway_rest_api.ingest.id}.execute-api.${var.aws_region}.amazonaws.com/${var.environment}/ingest"
}

output "api_key_value" {
  value     = aws_api_gateway_api_key.ingest.value
  sensitive = true
}

output "api_key_id" {
  value = aws_api_gateway_api_key.ingest.id
}
