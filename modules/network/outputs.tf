output "region" {
  description = "AWS region where this VPC network stack is deployed"
  value       = local.region_name
}

output "name_prefix" {
  description = "Standardized resource name prefix for this region"
  value       = local.name_prefix
}

output "vpc_id" {
  description = "ID of the regional VPC"
  value       = aws_vpc.this.id
}

output "vpc_cidr" {
  description = "CIDR block of the regional VPC"
  value       = aws_vpc.this.cidr_block
}

output "public_subnet_ids" {
  description = "List of Public Subnet IDs (for ALB and NAT Gateway)"
  value       = aws_subnet.public[*].id
}

output "private_app_subnet_ids" {
  description = "List of Private App Subnet IDs (for ECS Fargate tasks)"
  value       = aws_subnet.private_app[*].id
}

output "isolated_db_subnet_ids" {
  description = "List of Isolated DB Subnet IDs (for Aurora Global Database)"
  value       = aws_subnet.isolated_db[*].id
}

output "logs_kms_key_arn" {
  description = "ARN of the regional KMS key encrypting CloudWatch Log Groups"
  value       = aws_kms_key.network_logs.arn
}
