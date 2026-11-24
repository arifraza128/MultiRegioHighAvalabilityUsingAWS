variable "project_name" {
  description = "Short project identifier used in resource naming"
  type        = string
}

variable "environment" {
  description = "Deployment environment name (dev, staging, prod)"
  type        = string
}

variable "vpc_id" {
  description = "ID of the regional VPC"
  type        = string
}

variable "public_subnet_ids" {
  description = "List of Public Subnet IDs for the Application Load Balancer"
  type        = list(string)
}

variable "private_app_subnet_ids" {
  description = "List of Private App Subnet IDs for ECS Fargate tasks"
  type        = list(string)
}

variable "logs_kms_key_arn" {
  description = "ARN of the regional customer-managed KMS key for encrypting ECR and CloudWatch Logs"
  type        = string
}

variable "desired_count" {
  description = "Number of ECS Fargate tasks to run in this region (e.g., 2 in primary, 1 in warm standby)"
  type        = number
  default     = 2
}

variable "container_port" {
  description = "Container TCP port exposed by the Notes API"
  type        = number
  default     = 3000
}

variable "task_cpu" {
  description = "Fargate task CPU units (256 = 0.25 vCPU per AGENTS.md cost safety rule)"
  type        = number
  default     = 256
}

variable "task_memory" {
  description = "Fargate task memory in MiB (512 = 0.5 GB per AGENTS.md cost safety rule)"
  type        = number
  default     = 512
}

variable "image_tag" {
  description = "Container image tag deployed from the regional ECR repository"
  type        = string
  default     = "v1.0.0"
}

variable "is_primary_region" {
  description = "Whether this module instance is the primary region (controls ECR cross-region replication rule)"
  type        = bool
  default     = true
}

variable "ecr_replication_destination_region" {
  description = "Destination region for ECR cross-region replication (only used when is_primary_region = true)"
  type        = string
  default     = ""
}

variable "db_host" {
  description = "Regional Aurora cluster writer endpoint hostname (leave empty in Phase 2/3 for in-memory mode)"
  type        = string
  default     = ""
}

variable "db_port" {
  description = "Aurora PostgreSQL port"
  type        = number
  default     = 5432
}

variable "db_name" {
  description = "Aurora PostgreSQL database name"
  type        = string
  default     = "notesdb"
}

variable "db_secret_arn" {
  description = "Regional AWS Secrets Manager secret ARN holding database credentials (optional in Phase 2/3)"
  type        = string
  default     = ""
}

variable "db_kms_key_arn" {
  description = "Regional KMS key ARN used to decrypt the Secrets Manager database secret (optional in Phase 2/3)"
  type        = string
  default     = ""
}

variable "log_retention_days" {
  description = "CloudWatch Log Group retention in days for ECS application logs"
  type        = number
  default     = 7
}
