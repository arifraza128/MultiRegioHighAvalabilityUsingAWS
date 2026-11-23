variable "project_name" {
  description = "Short project identifier used in resource naming and tags"
  type        = string
  default     = "ha-notes"

  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.project_name))
    error_message = "project_name must contain only lowercase alphanumeric characters and hyphens."
  }
}

variable "environment" {
  description = "Deployment environment name (dev, staging, prod)"
  type        = string
  default     = "dev"
}

variable "owner" {
  description = "Owner identifier for mandatory cost attribution tags"
  type        = string
  default     = "cloud-architect"
}

variable "primary_region" {
  description = "Primary active AWS region"
  type        = string
  default     = "us-east-1"
}

variable "secondary_region" {
  description = "Secondary warm-standby DR AWS region"
  type        = string
  default     = "ap-south-1"

  validation {
    condition     = var.secondary_region != var.primary_region
    error_message = "secondary_region must be a different AWS region from primary_region."
  }
}

variable "primary_vpc_cidr" {
  description = "CIDR block for the primary region VPC"
  type        = string
  default     = "10.10.0.0/16"
}

variable "secondary_vpc_cidr" {
  description = "CIDR block for the secondary region VPC (non-overlapping with primary)"
  type        = string
  default     = "10.20.0.0/16"
}

variable "single_nat_gateway" {
  description = "Provision 1 NAT Gateway per region (true) to minimize test session cost, or 1 per AZ (false)"
  type        = bool
  default     = true
}

variable "primary_desired_count" {
  description = "Number of ECS Fargate tasks in the primary active region"
  type        = number
  default     = 2
}

variable "secondary_desired_count" {
  description = "Number of ECS Fargate tasks in the secondary warm-standby region"
  type        = number
  default     = 1
}

variable "custom_domain_name" {
  description = "Optional custom domain name for Route 53 & ACM certificates (leave empty to use default CloudFront/ALB domains)"
  type        = string
  default     = ""
}

variable "alert_email" {
  description = "Optional email address for CloudWatch Alarm SNS notifications"
  type        = string
  default     = ""
}

# ---------------------------------------------------------------------------
# Phase & Cost Control Feature Flags
# ---------------------------------------------------------------------------

variable "enable_secondary_region" {
  description = "Phase 3+: Deploy VPC and warm-standby ECS stack in secondary_region"
  type        = bool
  default     = false
}

variable "enable_aurora_global" {
  description = "Phase 4+: Deploy Aurora Global PostgreSQL cluster across primary and secondary regions"
  type        = bool
  default     = false
}

variable "enable_storage_cdn" {
  description = "Phase 5+: Deploy S3 Cross-Region Replication and CloudFront Origin Group"
  type        = bool
  default     = false
}

variable "enable_arc_cluster" {
  description = "Phase 6 & 9 ONLY: Deploy Route 53 ARC Cluster ($2.50/hr while active!), Routing Controls, and Safety Rule"
  type        = bool
  default     = false
}

variable "enable_monitoring" {
  description = "Phase 7+: Deploy CloudWatch Dashboards, Alarms (inc. AuroraGlobalDBReplicationLag), and SNS topics in both regions"
  type        = bool
  default     = false
}

variable "enable_fis" {
  description = "Phase 8+: Deploy AWS Fault Injection Service (FIS) experiment templates with CloudWatch Stop Conditions"
  type        = bool
  default     = false
}

variable "enable_failback_workflow" {
  description = "Phase 9+: Deploy AWS Step Functions automated failback state machine"
  type        = bool
  default     = false
}
