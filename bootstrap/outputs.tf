output "state_bucket_name" {
  description = "Name of the S3 bucket created for Terraform remote state"
  value       = aws_s3_bucket.tfstate.id
}

output "state_bucket_arn" {
  description = "ARN of the S3 bucket created for Terraform remote state"
  value       = aws_s3_bucket.tfstate.arn
}

output "lock_table_name" {
  description = "Name of the DynamoDB table used for Terraform state locking"
  value       = aws_dynamodb_table.tflock.name
}

output "kms_key_arn" {
  description = "ARN of the KMS key encrypting the Terraform remote state"
  value       = aws_kms_key.tfstate.arn
}

output "budget_name" {
  description = "Name of the AWS Budget guardrail alarm"
  value       = aws_budgets_budget.monthly_cost_guardrail.name
}
