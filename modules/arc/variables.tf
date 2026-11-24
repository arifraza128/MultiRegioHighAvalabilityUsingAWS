variable "project_name" {
  description = "Short project identifier used in resource naming"
  type        = string
}

variable "environment" {
  description = "Deployment environment name (dev, staging, prod)"
  type        = string
}

variable "primary_region" {
  description = "Primary active AWS region name"
  type        = string
}

variable "secondary_region" {
  description = "Secondary warm-standby AWS region name"
  type        = string
}

variable "primary_vpc_id" {
  description = "Primary VPC ID for associating the Route 53 private/test failover hosted zone"
  type        = string
}

variable "secondary_vpc_id" {
  description = "Secondary VPC ID for associating the Route 53 private/test failover hosted zone (optional)"
  type        = string
  default     = ""
}

variable "primary_alb_dns_name" {
  description = "DNS hostname of the primary region ALB"
  type        = string
}

variable "primary_alb_zone_id" {
  description = "Canonical hosted zone ID of the primary region ALB"
  type        = string
}

variable "secondary_alb_dns_name" {
  description = "DNS hostname of the secondary warm-standby region ALB"
  type        = string
  default     = ""
}

variable "secondary_alb_zone_id" {
  description = "Canonical hosted zone ID of the secondary warm-standby region ALB"
  type        = string
  default     = ""
}

variable "domain_name" {
  description = "Domain name for Route 53 ARC failover routing records"
  type        = string
  default     = "ha-notes.internal"
}
