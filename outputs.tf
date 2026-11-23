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
