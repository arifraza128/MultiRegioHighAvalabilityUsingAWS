output "account_id" {
  description = "Active AWS Account ID"
  value       = data.aws_caller_identity.current.account_id
}

output "primary_region" {
  description = "Configured primary active AWS region"
  value       = data.aws_region.primary.name
}

output "secondary_region" {
  description = "Configured secondary warm-standby AWS region"
  value       = data.aws_region.secondary.name
}

output "active_feature_flags" {
  description = "Summary of enabled phase feature flags for cost visibility"
  value = {
    enable_secondary_region  = var.enable_secondary_region
    enable_aurora_global     = var.enable_aurora_global
    enable_storage_cdn       = var.enable_storage_cdn
    enable_arc_cluster       = var.enable_arc_cluster
    enable_monitoring        = var.enable_monitoring
    enable_fis               = var.enable_fis
    enable_failback_workflow = var.enable_failback_workflow
  }
}

output "primary_vpc_id" {
  description = "VPC ID in the primary active region"
  value       = module.network_primary.vpc_id
}

output "primary_ecr_repository_url" {
  description = "ECR repository URL in the primary region"
  value       = module.ecs_primary.ecr_repository_url
}

output "primary_alb_dns_name" {
  description = "Public DNS hostname of the primary region Application Load Balancer"
  value       = module.ecs_primary.alb_dns_name
}

output "secondary_vpc_id" {
  description = "VPC ID in the secondary warm-standby region (when enable_secondary_region = true)"
  value       = var.enable_secondary_region ? module.network_secondary[0].vpc_id : null
}

output "secondary_ecr_repository_url" {
  description = "ECR repository URL in the secondary warm-standby region (when enable_secondary_region = true)"
  value       = var.enable_secondary_region ? module.ecs_secondary[0].ecr_repository_url : null
}

output "secondary_alb_dns_name" {
  description = "Public DNS hostname of the secondary warm-standby Application Load Balancer (when enable_secondary_region = true)"
  value       = var.enable_secondary_region ? module.ecs_secondary[0].alb_dns_name : null
}

output "aurora_global_cluster_id" {
  description = "Aurora Global Database cluster identifier (when enable_aurora_global = true)"
  value       = var.enable_aurora_global ? module.aurora_global[0].global_cluster_identifier : null
}

output "aurora_primary_writer_endpoint" {
  description = "Aurora primary cluster writer endpoint in us-east-1 (when enable_aurora_global = true)"
  value       = var.enable_aurora_global ? module.aurora_global[0].primary_cluster_endpoint : null
}

output "aurora_secondary_cluster_endpoint" {
  description = "Aurora secondary cluster endpoint in ap-south-1 (when enable_aurora_global = true)"
  value       = var.enable_aurora_global ? module.aurora_global[0].secondary_cluster_endpoint : null
}

output "cloudfront_domain_name" {
  description = "Default domain name of the CloudFront multi-region failover distribution (when enable_storage_cdn = true)"
  value       = var.enable_storage_cdn ? module.storage_cdn[0].cloudfront_domain_name : null
}

output "s3_primary_bucket_name" {
  description = "Name of the primary S3 static assets bucket (when enable_storage_cdn = true)"
  value       = var.enable_storage_cdn ? module.storage_cdn[0].primary_bucket_name : null
}

output "s3_secondary_bucket_name" {
  description = "Name of the secondary S3 replica bucket (when enable_storage_cdn = true)"
  value       = var.enable_storage_cdn ? module.storage_cdn[0].secondary_bucket_name : null
}

output "arc_cluster_endpoints" {
  description = "5 globally distributed Route 53 ARC cluster endpoints (when enable_arc_cluster = true)"
  value       = var.enable_arc_cluster ? module.arc[0].arc_cluster_endpoints : null
}

output "arc_primary_routing_control_arn" {
  description = "ARN of the Primary Region ARC Routing Control (when enable_arc_cluster = true)"
  value       = var.enable_arc_cluster ? module.arc[0].primary_routing_control_arn : null
}

output "arc_secondary_routing_control_arn" {
  description = "ARN of the Secondary Region ARC Routing Control (when enable_arc_cluster = true)"
  value       = var.enable_arc_cluster ? module.arc[0].secondary_routing_control_arn : null
}

output "primary_dashboard_name" {
  description = "CloudWatch Dashboard name in the primary region (when enable_monitoring = true)"
  value       = var.enable_monitoring ? module.monitoring_primary[0].dashboard_name : null
}

output "secondary_dashboard_name" {
  description = "CloudWatch Dashboard name in the secondary region (when enable_monitoring & enable_secondary_region = true)"
  value       = var.enable_monitoring && var.enable_secondary_region ? module.monitoring_secondary[0].dashboard_name : null
}

output "fis_ecs_task_termination_template_id" {
  description = "AWS FIS Experiment Template ID for primary ECS task termination (when enable_fis = true)"
  value       = var.enable_fis && var.enable_monitoring ? module.fis_primary[0].ecs_task_termination_template_id : null
}

output "failback_state_machine_arn" {
  description = "ARN of the Step Functions Failback Orchestrator in ap-south-1 (when enable_failback_workflow = true)"
  value       = var.enable_failback_workflow && var.enable_secondary_region ? module.failback_orchestrator[0].state_machine_arn : null
}
