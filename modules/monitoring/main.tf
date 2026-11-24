# =============================================================================
# Regional Monitoring, Dashboards & Alerting Module (Prompts 13 & 19)
# Deployed independently in BOTH us-east-1 and ap-south-1 so observability
# and alerting survive a complete loss of the primary region!
# =============================================================================

data "aws_region" "current" {}

locals {
  region_name = data.aws_region.current.name
  region_short_map = {
    "us-east-1"      = "use1"
    "us-east-2"      = "use2"
    "us-west-2"      = "usw2"
    "ap-south-1"     = "aps1"
    "eu-west-1"      = "euw1"
    "ap-southeast-1" = "apse1"
  }
  region_short = lookup(local.region_short_map, local.region_name, replace(local.region_name, "-", ""))
  name_prefix  = "${var.project_name}-${var.environment}-${local.region_short}"
  role_label   = var.is_primary_region ? "Primary" : "Secondary-Standby"
}

# -----------------------------------------------------------------------------
# 1. KMS-Encrypted Regional SNS Topic & Optional Email Subscription
# -----------------------------------------------------------------------------
resource "aws_sns_topic" "alerts" {
  name              = "${local.name_prefix}-ha-alerts"
  kms_master_key_id = var.logs_kms_key_arn
}

resource "aws_sns_topic_subscription" "email" {
  count     = var.alert_email != "" ? 1 : 0
  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = var.alert_email
}

# -----------------------------------------------------------------------------
# 2. Actionable CloudWatch Metric Alarms (ALB 5xx, Unhealthy Hosts, ECS Memory/CPU)
# -----------------------------------------------------------------------------
resource "aws_cloudwatch_metric_alarm" "alb_5xx_high" {
  alarm_name          = "${local.name_prefix}-alb-5xx-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "HTTPCode_Target_5XX_Count"
  namespace           = "AWS/ApplicationELB"
  period              = 60
  statistic           = "Sum"
  threshold           = var.alb_5xx_threshold
  alarm_description   = "[${local.role_label}] Regional ALB Target 5xx errors exceeded ${var.alb_5xx_threshold}/min in ${local.region_name}"
  treat_missing_data  = "notBreaching"

  dimensions = {
    LoadBalancer = var.alb_arn_suffix
  }

  alarm_actions = [aws_sns_topic.alerts.arn]
  ok_actions    = [aws_sns_topic.alerts.arn]
}

resource "aws_cloudwatch_metric_alarm" "alb_unhealthy_hosts" {
  alarm_name          = "${local.name_prefix}-alb-no-healthy-hosts"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = 2
  metric_name         = "HealthyHostCount"
  namespace           = "AWS/ApplicationELB"
  period              = 60
  statistic           = "Minimum"
  threshold           = 1
  alarm_description   = "[${local.role_label}] Regional ALB HealthyHostCount dropped below 1 in ${local.region_name}"
  treat_missing_data  = "breaching"

  dimensions = {
    LoadBalancer = var.alb_arn_suffix
    TargetGroup  = var.target_group_arn_suffix
  }

  alarm_actions = [aws_sns_topic.alerts.arn]
  ok_actions    = [aws_sns_topic.alerts.arn]
}

resource "aws_cloudwatch_metric_alarm" "ecs_cpu_high" {
  alarm_name          = "${local.name_prefix}-ecs-cpu-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 3
  metric_name         = "CPUUtilization"
  namespace           = "AWS/ECS"
  period              = 60
  statistic           = "Average"
  threshold           = 85
  alarm_description   = "[${local.role_label}] ECS Fargate CPU Utilization exceeded 85% in ${local.region_name}"
  treat_missing_data  = "notBreaching"

  dimensions = {
    ClusterName = var.ecs_cluster_name
    ServiceName = var.ecs_service_name
  }

  alarm_actions = [aws_sns_topic.alerts.arn]
}

# -----------------------------------------------------------------------------
# 3. Dedicated AWS FIS Stop-Condition Guardrail Alarm
#    Used by AWS FIS experiments to automatically abort fault injection if
#    unexpected guardrail thresholds breach.
# -----------------------------------------------------------------------------
resource "aws_cloudwatch_metric_alarm" "fis_stop_condition" {
  alarm_name          = "${local.name_prefix}-fis-stop-guardrail"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "HTTPCode_ELB_5XX_Count"
  namespace           = "AWS/ApplicationELB"
  period              = 60
  statistic           = "Sum"
  threshold           = 50
  alarm_description   = "AWS FIS Stop Condition Guardrail in ${local.region_name}: Halts active chaos experiment if ELB 5xx spikes > 50/min or manually tripped"
  treat_missing_data  = "notBreaching"

  dimensions = {
    LoadBalancer = var.alb_arn_suffix
  }

  alarm_actions = [aws_sns_topic.alerts.arn]
}

# -----------------------------------------------------------------------------
# 4. Regional CloudWatch Operational Dashboard (DESIGN.md Section 4)
# -----------------------------------------------------------------------------
resource "aws_cloudwatch_dashboard" "regional" {
  dashboard_name = "${local.name_prefix}-ha-dashboard"

  dashboard_body = jsonencode({
    widgets = [
      {
        type   = "metric"
        x      = 0
        y      = 0
        width  = 12
        height = 6
        properties = {
          title  = "${local.region_name} (${local.role_label}) - ALB Healthy Hosts & HTTP 5xx"
          region = local.region_name
          view   = "timeSeries"
          period = 60
          metrics = [
            ["AWS/ApplicationELB", "HealthyHostCount", "TargetGroup", var.target_group_arn_suffix, "LoadBalancer", var.alb_arn_suffix, { stat = "Minimum" }],
            ["AWS/ApplicationELB", "HTTPCode_Target_5XX_Count", "LoadBalancer", var.alb_arn_suffix, { stat = "Sum" }],
            ["AWS/ApplicationELB", "RequestCount", "LoadBalancer", var.alb_arn_suffix, { stat = "Sum" }]
          ]
        }
      },
      {
        type   = "metric"
        x      = 12
        y      = 0
        width  = 12
        height = 6
        properties = {
          title  = "${local.region_name} (${local.role_label}) - ALB Target Response Time (p95)"
          region = local.region_name
          view   = "timeSeries"
          period = 60
          metrics = [
            ["AWS/ApplicationELB", "TargetResponseTime", "LoadBalancer", var.alb_arn_suffix, { stat = "p95" }],
            ["AWS/ApplicationELB", "TargetResponseTime", "LoadBalancer", var.alb_arn_suffix, { stat = "Average" }]
          ]
        }
      },
      {
        type   = "metric"
        x      = 0
        y      = 6
        width  = 12
        height = 6
        properties = {
          title  = "${local.region_name} (${local.role_label}) - ECS Fargate CPU & Memory Utilization"
          region = local.region_name
          view   = "timeSeries"
          period = 60
          metrics = [
            ["AWS/ECS", "CPUUtilization", "ClusterName", var.ecs_cluster_name, "ServiceName", var.ecs_service_name, { stat = "Average" }],
            ["AWS/ECS", "MemoryUtilization", "ClusterName", var.ecs_cluster_name, "ServiceName", var.ecs_service_name, { stat = "Average" }]
          ]
        }
      },
      {
        type   = "metric"
        x      = 12
        y      = 6
        width  = 12
        height = 6
        properties = {
          title  = "${local.region_name} (${local.role_label}) - Aurora Global Replication Lag (ms) & Connections"
          region = local.region_name
          view   = "timeSeries"
          period = 60
          metrics = var.db_cluster_identifier != "" ? [
            ["AWS/RDS", "AuroraGlobalDBReplicationLag", "DBClusterIdentifier", var.db_cluster_identifier, { stat = "Maximum" }],
            ["AWS/RDS", "DatabaseConnections", "DBClusterIdentifier", var.db_cluster_identifier, { stat = "Maximum" }],
            ["AWS/RDS", "ServerlessDatabaseCapacity", "DBClusterIdentifier", var.db_cluster_identifier, { stat = "Average" }]
          ] : []
        }
      }
    ]
  })
}
