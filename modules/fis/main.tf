# =============================================================================
# AWS Fault Injection Service (FIS) Chaos Experiments Module (Phase 8)
# Every experiment template is bound to a mandatory CloudWatch Stop Condition
# alarm and logs execution events to a KMS-encrypted CloudWatch Log Group.
# NOTE (PRD.md Section 6.4): FIS simulates component/AZ failures within a
# region, NOT a true AWS regional control-plane collapse.
# =============================================================================

data "aws_region" "current" {}
data "aws_caller_identity" "current" {}

locals {
  region_name = data.aws_region.current.name
  account_id  = data.aws_caller_identity.current.account_id
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
}

# -----------------------------------------------------------------------------
# 1. KMS-Encrypted CloudWatch Log Group for FIS Experiment Audit Trail
# -----------------------------------------------------------------------------
resource "aws_cloudwatch_log_group" "fis" {
  name              = "/aws/fis/${local.name_prefix}-experiments"
  retention_in_days = 7
  kms_key_id        = var.logs_kms_key_arn
}

# -----------------------------------------------------------------------------
# 2. Least-Privilege IAM Role for AWS FIS (Prompt 11 Security Rule)
# -----------------------------------------------------------------------------
resource "aws_iam_role" "fis" {
  name = "${local.name_prefix}-fis-execution-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "fis.amazonaws.com"
        }
        Action = "sts:AssumeRole"
        Condition = {
          StringEquals = {
            "aws:SourceAccount" = local.account_id
          }
        }
      }
    ]
  })
}

resource "aws_iam_role_policy" "fis" {
  name = "${local.name_prefix}-fis-execution-policy"
  role = aws_iam_role.fis.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = concat(
      [
        {
          Sid    = "AllowStopTasksInPrimaryECSClusterOnly"
          Effect = "Allow"
          Action = [
            "ecs:ListTasks",
            "ecs:DescribeTasks",
            "ecs:StopTask"
          ]
          Resource = "*"
          Condition = {
            ArnEquals = {
              "ecs:cluster" = var.ecs_cluster_arn
            }
          }
        },
        {
          Sid    = "AllowDescribeECSClusterAndServices"
          Effect = "Allow"
          Action = [
            "ecs:DescribeClusters",
            "ecs:DescribeServices"
          ]
          Resource = [
            var.ecs_cluster_arn,
            "arn:aws:ecs:${local.region_name}:${local.account_id}:service/*"
          ]
        },
        {
          Sid    = "AllowWriteFISExecutionLogs"
          Effect = "Allow"
          Action = [
            "logs:CreateLogDelivery",
            "logs:PutResourcePolicy",
            "logs:DescribeResourcePolicies",
            "logs:DescribeLogGroups"
          ]
          Resource = "*"
        }
      ],
      var.db_cluster_arn != "" ? [
        {
          Sid    = "AllowFailoverPrimaryAuroraClusterOnly"
          Effect = "Allow"
          Action = [
            "rds:FailoverDBCluster",
            "rds:RebootDBInstance",
            "rds:DescribeDBClusters",
            "rds:DescribeDBInstances"
          ]
          Resource = [
            var.db_cluster_arn,
            "arn:aws:rds:${local.region_name}:${local.account_id}:db:${var.project_name}-${var.environment}-*"
          ]
        }
      ] : []
    )
  })
}

# -----------------------------------------------------------------------------
# 3. Experiment Template 1: Primary ECS Fargate Task Termination (100% Tasks)
#    Simulates total regional compute task collapse in us-east-1
# -----------------------------------------------------------------------------
resource "aws_fis_experiment_template" "ecs_task_termination" {
  description = "Terminate 100% of active ECS Fargate tasks in ${local.region_name} (${var.ecs_service_name}) with CloudWatch Stop Condition"
  role_arn    = aws_iam_role.fis.arn

  stop_condition {
    source = "aws:cloudwatch:alarm"
    value  = var.stop_condition_alarm_arn
  }

  action {
    name      = "StopAllPrimaryECSTasks"
    action_id = "aws:ecs:stop-task"

    target {
      key   = "Tasks"
      value = "PrimaryECSTasks"
    }
  }

  target {
    name           = "PrimaryECSTasks"
    resource_type  = "aws:ecs:task"
    selection_mode = "ALL"

    parameters = {
      cluster = var.ecs_cluster_arn
      service = var.ecs_service_name
    }
  }

  log_configuration {
    log_schema_version = 2
    cloudwatch_logs_configuration {
      log_group_arn = "${aws_cloudwatch_log_group.fis.arn}:*"
    }
  }

  tags = {
    Name = "${local.name_prefix}-fis-ecs-task-termination"
  }
}

# -----------------------------------------------------------------------------
# 4. Experiment Template 2: Primary Aurora Cluster Failover (When Aurora Enabled)
# -----------------------------------------------------------------------------
resource "aws_fis_experiment_template" "aurora_failover" {
  count       = var.db_cluster_arn != "" ? 1 : 0
  description = "Trigger Aurora PostgreSQL cluster failover in ${local.region_name} with CloudWatch Stop Condition"
  role_arn    = aws_iam_role.fis.arn

  stop_condition {
    source = "aws:cloudwatch:alarm"
    value  = var.stop_condition_alarm_arn
  }

  action {
    name      = "FailoverAuroraPrimaryCluster"
    action_id = "aws:rds:failover-db-cluster"

    target {
      key   = "Clusters"
      value = "PrimaryAuroraCluster"
    }
  }

  target {
    name           = "PrimaryAuroraCluster"
    resource_type  = "aws:rds:cluster"
    selection_mode = "ALL"
    resource_arns  = [var.db_cluster_arn]
  }

  log_configuration {
    log_schema_version = 2
    cloudwatch_logs_configuration {
      log_group_arn = "${aws_cloudwatch_log_group.fis.arn}:*"
    }
  }

  tags = {
    Name = "${local.name_prefix}-fis-aurora-failover"
  }
}
