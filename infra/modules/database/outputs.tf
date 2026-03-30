output "cluster_arn"    { value = aws_rds_cluster.aurora.arn }
output "cluster_endpoint" { value = aws_rds_cluster.aurora.endpoint }
output "secret_arn"     { value = aws_secretsmanager_secret.db.arn }
output "database_name"  { value = aws_rds_cluster.aurora.database_name }
