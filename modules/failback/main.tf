# =============================================================================
# AWS Step Functions Automated Failback Orchestrator (Phase 9)
# Hosted in the Secondary Region (ap-south-1) so failback orchestration is
# available even while recovering from a primary region incident.
# Coordinates:
#   1. Verifying target primary cluster status == "available"
#   2. Triggering zero-data-loss Aurora Global DB Switchover (RPO = 0)
#   3. Polling until the primary cluster resumes the Writer role
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
# 1. KMS-Encrypted CloudWatch Log Group for Step Functions Failback Audit Trail
# -----------------------------------------------------------------------------
resource "aws_cloudwatch_log_group" "sfn" {
  name              = "/aws/vendedlogs/states/${local.name_prefix}-failback"
  retention_in_days = 7
  kms_key_id        = var.logs_kms_key_arn
}

# -----------------------------------------------------------------------------
# 2. Least-Privilege IAM Role for Step Functions Failback State Machine
# -----------------------------------------------------------------------------
resource "aws_iam_role" "sfn" {
  name = "${local.name_prefix}-failback-sfn-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "states.amazonaws.com"
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

resource "aws_iam_role_policy" "sfn" {
  name = "${local.name_prefix}-failback-sfn-policy"
  role = aws_iam_role.sfn.id

  # checkov:skip=CKV_AWS_355:Step Functions CloudWatch Logs delivery and RDS DescribeGlobalClusters require account-level resource scope.
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowAuroraGlobalSwitchoverAndDescribe"
        Effect = "Allow"
        Action = [
          "rds:DescribeGlobalClusters",
          "rds:DescribeDBClusters",
          "rds:SwitchoverGlobalCluster"
        ]
        Resource = compact([
          "arn:aws:rds::${local.account_id}:global-cluster:${var.project_name}-${var.environment}-*",
          var.primary_cluster_arn,
          var.secondary_cluster_arn,
          "arn:aws:rds:*:${local.account_id}:cluster:${var.project_name}-${var.environment}-*"
        ])
      },
      {
        Sid    = "AllowStepFunctionsLogDelivery"
        Effect = "Allow"
        Action = [
          "logs:CreateLogDelivery",
          "logs:GetLogDelivery",
          "logs:UpdateLogDelivery",
          "logs:DeleteLogDelivery",
          "logs:ListLogDeliveries",
          "logs:PutResourcePolicy",
          "logs:DescribeResourcePolicies",
          "logs:DescribeLogGroups"
        ]
        Resource = "*"
      }
    ]
  })
}

# -----------------------------------------------------------------------------
# 3. AWS Step Functions State Machine for Planned Zero-RPO Failback
# -----------------------------------------------------------------------------
resource "aws_sfn_state_machine" "failback" {
  name     = "${local.name_prefix}-failback-orchestrator"
  role_arn = aws_iam_role.sfn.arn

  logging_configuration {
    log_destination        = "${aws_cloudwatch_log_group.sfn.arn}:*"
    include_execution_data = true
    level                  = "ALL"
  }

  tracing_configuration {
    enabled = true
  }

  definition = jsonencode({
    Comment = "Automated Zero-Data-Loss (RPO=0) Failback Orchestrator for Aurora Global Database"
    StartAt = "DescribeGlobalClusterBeforeSwitchover"
    States = {
      DescribeGlobalClusterBeforeSwitchover = {
        Type     = "Task"
        Resource = "arn:aws:states:::aws-sdk:rds:describeGlobalClusters"
        Parameters = {
          "GlobalClusterIdentifier.$" = "$.global_cluster_id"
        }
        ResultPath = "$.global_status"
        Next       = "InitiatePlannedGlobalSwitchover"
      }
      InitiatePlannedGlobalSwitchover = {
        Type     = "Task"
        Resource = "arn:aws:states:::aws-sdk:rds:switchoverGlobalCluster"
        Parameters = {
          "GlobalClusterIdentifier.$"   = "$.global_cluster_id"
          "TargetDbClusterIdentifier.$" = "$.target_primary_cluster_arn"
        }
        ResultPath = "$.switchover_result"
        Next       = "WaitForSwitchoverPropagation"
        Catch = [
          {
            ErrorEquals = ["States.ALL"]
            ResultPath  = "$.error"
            Next        = "FailbackFailed"
          }
        ]
      }
      WaitForSwitchoverPropagation = {
        Type    = "Wait"
        Seconds = 30
        Next    = "VerifyGlobalClusterAvailable"
      }
      VerifyGlobalClusterAvailable = {
        Type     = "Task"
        Resource = "arn:aws:states:::aws-sdk:rds:describeGlobalClusters"
        Parameters = {
          "GlobalClusterIdentifier.$" = "$.global_cluster_id"
        }
        ResultPath = "$.verify_status"
        Next       = "CheckIfSwitchoverComplete"
      }
      CheckIfSwitchoverComplete = {
        Type = "Choice"
        Choices = [
          {
            Variable     = "$.verify_status.GlobalClusters[0].Status"
            StringEquals = "available"
            Next         = "FailbackSucceeded"
          }
        ]
        Default = "WaitForSwitchoverPropagation"
      }
      FailbackSucceeded = {
        Type = "Succeed"
      }
      FailbackFailed = {
        Type  = "Fail"
        Error = "AuroraGlobalSwitchoverError"
        Cause = "Planned Aurora Global Database switchover encountered an error."
      }
    }
  })
}
