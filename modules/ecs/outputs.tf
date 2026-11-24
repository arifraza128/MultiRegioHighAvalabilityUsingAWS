output "region" {
  description = "AWS region of this ECS & ALB deployment"
  value       = local.region_name
}

output "ecr_repository_url" {
  description = "URL of the regional ECR repository"
  value       = aws_ecr_repository.app.repository_url
}

output "ecr_repository_arn" {
  description = "ARN of the regional ECR repository"
  value       = aws_ecr_repository.app.arn
}

output "alb_arn" {
  description = "ARN of the regional Application Load Balancer"
  value       = aws_lb.this.arn
}

output "alb_arn_suffix" {
  description = "ARN suffix of the regional ALB (for CloudWatch metric dimensions)"
  value       = aws_lb.this.arn_suffix
}

output "alb_dns_name" {
  description = "Public DNS hostname of the regional Application Load Balancer"
  value       = aws_lb.this.dns_name
}

output "alb_zone_id" {
  description = "Canonical Hosted Zone ID of the regional ALB (for Route 53 Alias records)"
  value       = aws_lb.this.zone_id
}

output "target_group_arn" {
  description = "ARN of the regional ALB Target Group"
  value       = aws_lb_target_group.app.arn
}

output "target_group_arn_suffix" {
  description = "ARN suffix of the regional ALB Target Group (for CloudWatch metric dimensions)"
  value       = aws_lb_target_group.app.arn_suffix
}

output "ecs_cluster_name" {
  description = "Name of the regional ECS Cluster"
  value       = aws_ecs_cluster.this.name
}

output "ecs_cluster_arn" {
  description = "ARN of the regional ECS Cluster"
  value       = aws_ecs_cluster.this.arn
}

output "ecs_service_name" {
  description = "Name of the regional ECS Fargate Service"
  value       = aws_ecs_service.app.name
}

output "ecs_tasks_security_group_id" {
  description = "Security Group ID attached to ECS Fargate tasks (used to allow inbound 5432 to Aurora)"
  value       = aws_security_group.ecs_tasks.id
}

output "ecs_execution_role_arn" {
  description = "ARN of the regional ECS Task Execution IAM Role"
  value       = aws_iam_role.execution.arn
}

output "ecs_task_role_arn" {
  description = "ARN of the regional ECS Runtime Task IAM Role"
  value       = aws_iam_role.task.arn
}
