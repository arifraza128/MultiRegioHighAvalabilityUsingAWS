variable "project_name" {
  description = "Short project identifier used in resource naming"
  type        = string
}

variable "environment" {
  description = "Deployment environment name (dev, staging, prod)"
  type        = string
}

variable "custom_domain_name" {
  description = "Optional custom domain name for CloudFront & ACM certificate in us-east-1 (leave empty for default *.cloudfront.net cert)"
  type        = string
  default     = ""
}
