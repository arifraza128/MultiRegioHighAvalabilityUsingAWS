output "fis_role_arn" {
  description = "ARN of the least-privilege AWS FIS execution IAM role"
  value       = aws_iam_role.fis.arn
}

output "ecs_task_termination_template_id" {
  description = "ID of the AWS FIS Experiment Template for terminating primary ECS tasks"
  value       = aws_fis_experiment_template.ecs_task_termination.id
}

output "aurora_failover_template_id" {
  description = "ID of the AWS FIS Experiment Template for failing over the primary Aurora cluster (when Aurora enabled)"
  value       = var.db_cluster_arn != "" ? aws_fis_experiment_template.aurora_failover[0].id : ""
}

output "fis_log_group_name" {
  description = "CloudWatch Log Group capturing AWS FIS experiment execution logs"
  value       = aws_cloudwatch_log_group.fis.name
}
