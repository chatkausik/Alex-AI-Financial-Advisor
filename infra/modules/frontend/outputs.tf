output "cloudfront_url"     { value = "https://${aws_cloudfront_distribution.main.domain_name}" }
output "cloudfront_id"      { value = aws_cloudfront_distribution.main.id }
output "api_gateway_url"    { value = aws_apigatewayv2_api.main.api_endpoint }
output "s3_bucket"          { value = aws_s3_bucket.frontend.id }
output "api_lambda_name"    { value = aws_lambda_function.api.function_name }
