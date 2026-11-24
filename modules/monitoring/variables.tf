variable "project_name" {
  description = "Short project identifier used in resource naming"
  type        = string
}

variable "environment" {
  description = "Deployment environment name (dev, staging, prod)"
  type        = string
}

variable "logs_kms_key_arn" {
  description = "Regional customer-managed KMS key ARN for encrypting the regional SNS alerting topic"
  type        = string
}

variable "alb_arn_suffix" {
  description = "ARN suffix of the regional Application Load Balancer for CloudWatch dimensions"
  type        = string
}

variable "target_group_arn_suffix" {
  description = "ARN suffix of the regional ALB Target Group for CloudWatch dimensions"
  type        = string
}

variable "ecs_cluster_name" {
  description = "Name of the regional ECS Cluster"
  type        = string
}

variable "ecs_service_name" {
  description = "Name of the regional ECS Fargate Service"
  type        = string
}

variable "db_cluster_identifier" {
  description = "Regional Aurora DB Cluster Identifier (optional when Aurora Global is disabled)"
  type        = string
  default     = ""
}

variable "is_primary_region" {
  description = "Whether this monitoring instance is deployed in the primary active region"
  type        = bool
  default     = true
}

variable "alert_email" {
  description = "Optional email address to subscribe to the regional SNS alerts topic"
  type        = string
  default     = ""
}

variable "alb_5xx_threshold" {
  description = "Maximum allowed ALB HTTP 5xx count per minute before firing alarm"
  type        = number
  default     = 5
}
