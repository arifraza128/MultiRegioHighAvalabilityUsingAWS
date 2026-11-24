output "arc_cluster_arn" {
  description = "ARN of the Route 53 ARC Cluster"
  value       = aws_route53recoverycontrolconfig_cluster.this.arn
}

output "arc_cluster_endpoints" {
  description = "5 globally distributed data-plane endpoints for toggling ARC Routing Controls"
  value       = aws_route53recoverycontrolconfig_cluster.this.cluster_endpoints
}

output "arc_control_panel_arn" {
  description = "ARN of the Route 53 ARC Control Panel"
  value       = aws_route53recoverycontrolconfig_control_panel.this.arn
}

output "primary_routing_control_arn" {
  description = "ARN of the Primary Region (us-east-1) ARC Routing Control"
  value       = aws_route53recoverycontrolconfig_routing_control.primary.arn
}

output "secondary_routing_control_arn" {
  description = "ARN of the Secondary Region (ap-south-1) ARC Routing Control"
  value       = aws_route53recoverycontrolconfig_routing_control.secondary.arn
}

output "safety_rule_arn" {
  description = "ARN of the Assertion Safety Rule (ATLEAST 1 ON)"
  value       = aws_route53recoverycontrolconfig_safety_rule.at_least_one_active.arn
}

output "primary_health_check_id" {
  description = "Route 53 Health Check ID bound to the Primary ARC Routing Control"
  value       = aws_route53_health_check.primary_arc.id
}

output "secondary_health_check_id" {
  description = "Route 53 Health Check ID bound to the Secondary ARC Routing Control"
  value       = aws_route53_health_check.secondary_arc.id
}

output "failover_dns_fqdn" {
  description = "Fully qualified domain name of the ARC-controlled failover API record"
  value       = aws_route53_record.api_primary.fqdn
}
