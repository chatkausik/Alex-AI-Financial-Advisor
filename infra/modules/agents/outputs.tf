output "sqs_queue_url"  { value = aws_sqs_queue.jobs.url }
output "sqs_queue_arn"  { value = aws_sqs_queue.jobs.arn }
output "planner_arn"    { value = aws_lambda_function.planner.arn }
output "packages_bucket" { value = aws_s3_bucket.packages.id }
