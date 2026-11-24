variable "project_name" {
  description = "Short project identifier used in resource naming"
  type        = string
}

variable "environment" {
  description = "Deployment environment name (dev, staging, prod)"
  type        = string
}

variable "enable_secondary_region" {
  description = "Whether to provision the secondary region replica cluster and secret replica"
  type        = bool
  default     = true
}

variable "primary_vpc_id" {
  description = "VPC ID in the primary region"
  type        = string
}

variable "primary_db_subnet_ids" {
  description = "Isolated database subnet IDs in the primary region"
  type        = list(string)
}

variable "primary_ecs_security_group_id" {
  description = "ECS Fargate Tasks Security Group ID in the primary region allowed to connect on port 5432"
  type        = string
}

variable "secondary_vpc_id" {
  description = "VPC ID in the secondary warm-standby region"
  type        = string
  default     = ""
}

variable "secondary_db_subnet_ids" {
  description = "Isolated database subnet IDs in the secondary warm-standby region"
  type        = list(string)
  default     = []
}

variable "secondary_ecs_security_group_id" {
  description = "ECS Fargate Tasks Security Group ID in the secondary region allowed to connect on port 5432"
  type        = string
  default     = ""
}

variable "engine_version" {
  description = "Aurora PostgreSQL engine version supporting Global Database and Serverless v2"
  type        = string
  default     = "16.4"
}

variable "database_name" {
  description = "Initial database name created in the Aurora Global Cluster"
  type        = string
  default     = "notesdb"
}

variable "master_username" {
  description = "Master administrator username for Aurora PostgreSQL"
  type        = string
  default     = "notes_admin"
}

variable "min_acu_capacity" {
  description = "Minimum Aurora Serverless v2 capacity in ACUs (0.5 ACU for cost safety)"
  type        = number
  default     = 0.5
}

variable "max_acu_capacity" {
  description = "Maximum Aurora Serverless v2 capacity in ACUs"
  type        = number
  default     = 2.0
}

variable "replication_lag_alarm_threshold_ms" {
  description = "Threshold in milliseconds for the AuroraGlobalDBReplicationLag CloudWatch alarm in the secondary region"
  type        = number
  default     = 5000
}
