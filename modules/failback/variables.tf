variable "project_name" {
  description = "Short project identifier used in resource naming"
  type        = string
}

variable "environment" {
  description = "Deployment environment name (dev, staging, prod)"
  type        = string
}

variable "global_cluster_identifier" {
  description = "Aurora Global Database cluster identifier"
  type        = string
  default     = ""
}

variable "primary_cluster_arn" {
  description = "ARN of the primary region (us-east-1) Aurora cluster"
  type        = string
  default     = ""
}

variable "secondary_cluster_arn" {
  description = "ARN of the secondary region (ap-south-1) Aurora cluster"
  type        = string
  default     = ""
}

variable "logs_kms_key_arn" {
  description = "Regional customer-managed KMS key ARN for encrypting Step Functions logs"
  type        = string
}
