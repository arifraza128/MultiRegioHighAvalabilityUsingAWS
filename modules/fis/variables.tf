variable "project_name" {
  description = "Short project identifier used in resource naming"
  type        = string
}

variable "environment" {
  description = "Deployment environment name (dev, staging, prod)"
  type        = string
}

variable "ecs_cluster_arn" {
  description = "ARN of the primary region ECS cluster targeted by fault injection"
  type        = string
}

variable "ecs_service_name" {
  description = "Name of the primary region ECS service targeted by fault injection"
  type        = string
}

variable "db_cluster_arn" {
  description = "ARN of the primary region Aurora DB cluster for DB failover fault injection (optional)"
  type        = string
  default     = ""
}

variable "stop_condition_alarm_arn" {
  description = "Mandatory CloudWatch Alarm ARN that immediately halts FIS experiments when breached"
  type        = string
}

variable "logs_kms_key_arn" {
  description = "Regional customer-managed KMS key ARN for encrypting FIS execution logs"
  type        = string
}
