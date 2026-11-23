variable "project_name" {
  description = "Short project identifier used in resource naming and tags"
  type        = string
  default     = "ha-notes"
}

variable "environment" {
  description = "Deployment environment name (e.g., dev, prod)"
  type        = string
  default     = "dev"
}

variable "primary_region" {
  description = "AWS region hosting the Terraform remote state bucket and global budget alarm"
  type        = string
  default     = "us-east-1"
}

variable "owner" {
  description = "Owner tag value for cost attribution"
  type        = string
  default     = "cloud-architect"
}

variable "budget_alert_email" {
  description = "Email address to receive AWS Budget threshold alerts ($10, $25, $50)"
  type        = string
  default     = "alerts@example.com"
}

variable "monthly_budget_limit_usd" {
  description = "Monthly AWS Budget ceiling in USD for this project"
  type        = string
  default     = "25"
}
