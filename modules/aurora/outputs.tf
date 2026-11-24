output "global_cluster_identifier" {
  description = "Identifier of the Aurora Global Database cluster"
  value       = aws_rds_global_cluster.this.id
}

output "primary_cluster_arn" {
  description = "ARN of the primary Aurora regional cluster"
  value       = aws_rds_cluster.primary.arn
}

output "primary_cluster_identifier" {
  description = "Identifier of the primary Aurora regional cluster"
  value       = aws_rds_cluster.primary.cluster_identifier
}

output "primary_cluster_endpoint" {
  description = "Writer endpoint hostname of the primary Aurora cluster"
  value       = aws_rds_cluster.primary.endpoint
}

output "primary_secret_arn" {
  description = "Secrets Manager ARN holding database credentials in the primary region"
  value       = aws_secretsmanager_secret.db_credentials.arn
}

output "primary_kms_key_arn" {
  description = "KMS key ARN encrypting Aurora and Secrets Manager in the primary region"
  value       = aws_kms_key.primary_db.arn
}

output "secondary_cluster_arn" {
  description = "ARN of the secondary Aurora regional cluster (when enabled)"
  value       = var.enable_secondary_region ? aws_rds_cluster.secondary[0].arn : ""
}

output "secondary_cluster_identifier" {
  description = "Identifier of the secondary Aurora regional cluster (when enabled)"
  value       = var.enable_secondary_region ? aws_rds_cluster.secondary[0].cluster_identifier : ""
}

output "secondary_cluster_endpoint" {
  description = "Cluster endpoint hostname of the secondary Aurora cluster (resolves to writer upon promotion)"
  value       = var.enable_secondary_region ? aws_rds_cluster.secondary[0].endpoint : ""
}

output "secondary_secret_arn" {
  description = "Replicated Secrets Manager ARN holding database credentials in the secondary region"
  value       = local.secondary_secret_arn
}

output "secondary_kms_key_arn" {
  description = "KMS key ARN encrypting Aurora and Secrets Manager in the secondary region"
  value       = var.enable_secondary_region ? aws_kms_key.secondary_db[0].arn : ""
}

output "replication_lag_alarm_arn" {
  description = "ARN of the AuroraGlobalDBReplicationLag CloudWatch alarm in the secondary region"
  value       = var.enable_secondary_region ? aws_cloudwatch_metric_alarm.replication_lag_high[0].arn : ""
}
