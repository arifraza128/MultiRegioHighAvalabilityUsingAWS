variable "project_name" {
  description = "Short project identifier used in resource naming"
  type        = string
}

variable "environment" {
  description = "Deployment environment name (dev, staging, prod)"
  type        = string
}

variable "vpc_cidr" {
  description = "CIDR block for the regional VPC (e.g., 10.10.0.0/16 or 10.20.0.0/16)"
  type        = string
}

variable "az_count" {
  description = "Number of Availability Zones to span (minimum 2 for ALB and Aurora HA)"
  type        = number
  default     = 2

  validation {
    condition     = var.az_count >= 2 && var.az_count <= 3
    error_message = "az_count must be 2 or 3."
  }
}

variable "single_nat_gateway" {
  description = "Provision 1 NAT Gateway per region (true) for cost savings, or 1 per AZ (false)"
  type        = bool
  default     = true
}

variable "flow_log_retention_days" {
  description = "CloudWatch Log Group retention in days for VPC Flow Logs"
  type        = number
  default     = 7
}
