output "state_machine_arn" {
  description = "ARN of the AWS Step Functions Failback Orchestrator State Machine"
  value       = aws_sfn_state_machine.failback.arn
}

output "state_machine_name" {
  description = "Name of the AWS Step Functions Failback Orchestrator State Machine"
  value       = aws_sfn_state_machine.failback.name
}

output "sfn_role_arn" {
  description = "ARN of the least-privilege IAM role used by the Step Functions Failback State Machine"
  value       = aws_iam_role.sfn.arn
}
