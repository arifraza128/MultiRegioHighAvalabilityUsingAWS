output "sns_topic_arn" {
  description = "ARN of the regional KMS-encrypted SNS alerts topic"
  value       = aws_sns_topic.alerts.arn
}

output "alb_5xx_alarm_arn" {
  description = "ARN of the regional ALB HTTP 5xx alarm"
  value       = aws_cloudwatch_metric_alarm.alb_5xx_high.arn
}

output "alb_unhealthy_hosts_alarm_arn" {
  description = "ARN of the regional ALB HealthyHostCount alarm"
  value       = aws_cloudwatch_metric_alarm.alb_unhealthy_hosts.arn
}

output "fis_stop_condition_alarm_arn" {
  description = "ARN of the CloudWatch Alarm used as the mandatory AWS FIS Stop Condition guardrail"
  value       = aws_cloudwatch_metric_alarm.fis_stop_condition.arn
}

output "fis_stop_condition_alarm_name" {
  description = "Name of the CloudWatch Alarm used as the mandatory AWS FIS Stop Condition guardrail"
  value       = aws_cloudwatch_metric_alarm.fis_stop_condition.alarm_name
}

output "dashboard_name" {
  description = "Name of the regional CloudWatch operational dashboard"
  value       = aws_cloudwatch_dashboard.regional.dashboard_name
}
