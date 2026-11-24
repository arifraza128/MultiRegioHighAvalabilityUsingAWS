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
