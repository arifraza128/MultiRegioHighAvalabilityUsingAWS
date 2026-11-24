data "aws_caller_identity" "current" {
  provider = aws.primary
}

data "aws_region" "primary" {
  provider = aws.primary
}

data "aws_region" "secondary" {
  provider = aws.secondary
}

locals {
  account_id       = data.aws_caller_identity.current.account_id
  primary_region   = data.aws_region.primary.name
  secondary_region = data.aws_region.secondary.name

  region_short_map = {
    "us-east-1"      = "use1"
    "us-east-2"      = "use2"
    "us-west-2"      = "usw2"
    "ap-south-1"     = "aps1"
    "eu-west-1"      = "euw1"
    "ap-southeast-1" = "apse1"
  }

  primary_short   = lookup(local.region_short_map, local.primary_region, replace(local.primary_region, "-", ""))
  secondary_short = lookup(local.region_short_map, local.secondary_region, replace(local.secondary_region, "-", ""))

  global_prefix    = "${var.project_name}-${var.environment}"
  primary_prefix   = "${var.project_name}-${var.environment}-${local.primary_short}"
  secondary_prefix = "${var.project_name}-${var.environment}-${local.secondary_short}"
}

# -----------------------------------------------------------------------------
# 1. Customer-Managed KMS Keys in Both Regions (Aurora & Secrets Manager)
# -----------------------------------------------------------------------------
resource "aws_kms_key" "primary_db" {
  provider                = aws.primary
  description             = "KMS key for Aurora Global Primary and Secrets Manager in ${local.primary_region}"
  deletion_window_in_days = 7
  enable_key_rotation     = true

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "EnableRootAccountPermissions"
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${local.account_id}:root"
        }
        Action   = "kms:*"
        Resource = "*"
      }
    ]
  })
}

resource "aws_kms_alias" "primary_db" {
  provider      = aws.primary
  name          = "alias/${local.primary_prefix}-aurora-kms"
  target_key_id = aws_kms_key.primary_db.key_id
}

resource "aws_kms_key" "secondary_db" {
  count                   = var.enable_secondary_region ? 1 : 0
  provider                = aws.secondary
  description             = "KMS key for Aurora Global Secondary and Replicated Secrets in ${local.secondary_region}"
  deletion_window_in_days = 7
  enable_key_rotation     = true

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "EnableRootAccountPermissions"
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${local.account_id}:root"
        }
        Action   = "kms:*"
        Resource = "*"
      }
    ]
  })
}

resource "aws_kms_alias" "secondary_db" {
  count         = var.enable_secondary_region ? 1 : 0
  provider      = aws.secondary
  name          = "alias/${local.secondary_prefix}-aurora-kms"
  target_key_id = aws_kms_key.secondary_db[0].key_id
}

# -----------------------------------------------------------------------------
# 2. Random Master Password & Secrets Manager Cross-Region Replication
# -----------------------------------------------------------------------------
resource "random_password" "db_master" {
  length           = 32
  special          = true
  override_special = "!#$%&*()-_=+[]{}<>:?"
}

resource "random_id" "secret_suffix" {
  byte_length = 4
}

resource "aws_secretsmanager_secret" "db_credentials" {
  provider                = aws.primary
  name                    = "${local.global_prefix}-aurora-credentials-${random_id.secret_suffix.hex}"
  description             = "Aurora Global PostgreSQL master credentials (replicated to ${local.secondary_region})"
  kms_key_id              = aws_kms_key.primary_db.arn
  recovery_window_in_days = 0

  dynamic "replica" {
    for_each = var.enable_secondary_region ? [1] : []
    content {
      region     = local.secondary_region
      kms_key_id = aws_kms_key.secondary_db[0].arn
    }
  }
}

resource "aws_secretsmanager_secret_version" "db_credentials" {
  provider  = aws.primary
  secret_id = aws_secretsmanager_secret.db_credentials.id

  secret_string = jsonencode({
    username = var.master_username
    password = random_password.db_master.result
    dbname   = var.database_name
    engine   = "aurora-postgresql"
    port     = 5432
  })
}

# Construct the deterministic ARN of the replicated secret in the secondary region
locals {
  secondary_secret_arn = var.enable_secondary_region ? replace(
    aws_secretsmanager_secret.db_credentials.arn,
    ":secretsmanager:${local.primary_region}:",
    ":secretsmanager:${local.secondary_region}:"
  ) : ""
}

# -----------------------------------------------------------------------------
# 3. DB Subnet Groups & Security Groups (Primary & Secondary)
# -----------------------------------------------------------------------------
resource "aws_db_subnet_group" "primary" {
  provider    = aws.primary
  name        = "${local.primary_prefix}-db-subnets"
  description = "Isolated Aurora subnets in ${local.primary_region}"
  subnet_ids  = var.primary_db_subnet_ids
}

resource "aws_security_group" "primary_db" {
  provider    = aws.primary
  name        = "${local.primary_prefix}-aurora-sg"
  description = "Aurora PostgreSQL security group in ${local.primary_region}"
  vpc_id      = var.primary_vpc_id

  tags = {
    Name = "${local.primary_prefix}-aurora-sg"
  }
}

resource "aws_vpc_security_group_ingress_rule" "primary_db_from_ecs" {
  provider                     = aws.primary
  security_group_id            = aws_security_group.primary_db.id
  description                  = "Allow PostgreSQL 5432 strictly from regional ECS Fargate tasks"
  referenced_security_group_id = var.primary_ecs_security_group_id
  from_port                    = 5432
  to_port                      = 5432
  ip_protocol                  = "tcp"
}

resource "aws_db_subnet_group" "secondary" {
  count       = var.enable_secondary_region ? 1 : 0
  provider    = aws.secondary
  name        = "${local.secondary_prefix}-db-subnets"
  description = "Isolated Aurora subnets in ${local.secondary_region}"
  subnet_ids  = var.secondary_db_subnet_ids
}

resource "aws_security_group" "secondary_db" {
  count       = var.enable_secondary_region ? 1 : 0
  provider    = aws.secondary
  name        = "${local.secondary_prefix}-aurora-sg"
  description = "Aurora PostgreSQL security group in ${local.secondary_region}"
  vpc_id      = var.secondary_vpc_id

  tags = {
    Name = "${local.secondary_prefix}-aurora-sg"
  }
}

resource "aws_vpc_security_group_ingress_rule" "secondary_db_from_ecs" {
  count                        = var.enable_secondary_region ? 1 : 0
  provider                     = aws.secondary
  security_group_id            = aws_security_group.secondary_db[0].id
  description                  = "Allow PostgreSQL 5432 strictly from regional ECS Fargate tasks"
  referenced_security_group_id = var.secondary_ecs_security_group_id
  from_port                    = 5432
  to_port                      = 5432
  ip_protocol                  = "tcp"
}

# -----------------------------------------------------------------------------
# 4. Aurora Global Cluster + Primary Writer Cluster (us-east-1)
# -----------------------------------------------------------------------------
resource "aws_rds_global_cluster" "this" {
  provider                  = aws.primary
  global_cluster_identifier = "${local.global_prefix}-global-db"
  engine                    = "aurora-postgresql"
  engine_version            = var.engine_version
  database_name             = var.database_name
  storage_encrypted         = true
  deletion_protection       = false
}

resource "aws_rds_cluster" "primary" {
  provider                            = aws.primary
  cluster_identifier                  = "${local.primary_prefix}-aurora-cluster"
  global_cluster_identifier           = aws_rds_global_cluster.this.id
  engine                              = aws_rds_global_cluster.this.engine
  engine_version                      = aws_rds_global_cluster.this.engine_version
  database_name                       = var.database_name
  master_username                     = var.master_username
  master_password                     = random_password.db_master.result
  db_subnet_group_name                = aws_db_subnet_group.primary.name
  vpc_security_group_ids              = [aws_security_group.primary_db.id]
  storage_encrypted                   = true
  kms_key_id                          = aws_kms_key.primary_db.arn
  backup_retention_period             = 1
  skip_final_snapshot                 = true
  deletion_protection                 = false
  iam_database_authentication_enabled = true
  enabled_cloudwatch_logs_exports     = ["postgresql"]

  serverlessv2_scaling_configuration {
    min_capacity = var.min_acu_capacity
    max_capacity = var.max_acu_capacity
  }
}

resource "aws_rds_cluster_instance" "primary_writer" {
  provider                        = aws.primary
  identifier                      = "${local.primary_prefix}-aurora-writer-1"
  cluster_identifier              = aws_rds_cluster.primary.id
  instance_class                  = "db.serverless"
  engine                          = aws_rds_cluster.primary.engine
  engine_version                  = aws_rds_cluster.primary.engine_version
  db_subnet_group_name            = aws_db_subnet_group.primary.name
  publicly_accessible             = false
  auto_minor_version_upgrade      = true
  performance_insights_enabled    = true
  performance_insights_kms_key_id = aws_kms_key.primary_db.arn
}

# -----------------------------------------------------------------------------
# 5. Secondary Read-Replica Cluster (ap-south-1)
# -----------------------------------------------------------------------------
resource "aws_rds_cluster" "secondary" {
  count                               = var.enable_secondary_region ? 1 : 0
  provider                            = aws.secondary
  cluster_identifier                  = "${local.secondary_prefix}-aurora-cluster"
  global_cluster_identifier           = aws_rds_global_cluster.this.id
  engine                              = aws_rds_global_cluster.this.engine
  engine_version                      = aws_rds_global_cluster.this.engine_version
  db_subnet_group_name                = aws_db_subnet_group.secondary[0].name
  vpc_security_group_ids              = [aws_security_group.secondary_db[0].id]
  storage_encrypted                   = true
  kms_key_id                          = aws_kms_key.secondary_db[0].arn
  source_region                       = local.primary_region
  backup_retention_period             = 1
  skip_final_snapshot                 = true
  deletion_protection                 = false
  iam_database_authentication_enabled = true
  enabled_cloudwatch_logs_exports     = ["postgresql"]

  serverlessv2_scaling_configuration {
    min_capacity = var.min_acu_capacity
    max_capacity = var.max_acu_capacity
  }

  depends_on = [aws_rds_cluster_instance.primary_writer]

  lifecycle {
    ignore_changes = [
      replication_source_identifier,
      global_cluster_identifier
    ]
  }
}

resource "aws_rds_cluster_instance" "secondary_reader" {
  count                           = var.enable_secondary_region ? 1 : 0
  provider                        = aws.secondary
  identifier                      = "${local.secondary_prefix}-aurora-reader-1"
  cluster_identifier              = aws_rds_cluster.secondary[0].id
  instance_class                  = "db.serverless"
  engine                          = aws_rds_cluster.secondary[0].engine
  engine_version                  = aws_rds_cluster.secondary[0].engine_version
  db_subnet_group_name            = aws_db_subnet_group.secondary[0].name
  publicly_accessible             = false
  auto_minor_version_upgrade      = true
  performance_insights_enabled    = true
  performance_insights_kms_key_id = aws_kms_key.secondary_db[0].arn
}

# -----------------------------------------------------------------------------
# 6. Mandatory AuroraGlobalDBReplicationLag Alarm in Secondary Region
# -----------------------------------------------------------------------------
resource "aws_cloudwatch_metric_alarm" "replication_lag_high" {
  count               = var.enable_secondary_region ? 1 : 0
  provider            = aws.secondary
  alarm_name          = "${local.secondary_prefix}-aurora-global-replication-lag-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "AuroraGlobalDBReplicationLag"
  namespace           = "AWS/RDS"
  period              = 60
  statistic           = "Maximum"
  threshold           = var.replication_lag_alarm_threshold_ms
  alarm_description   = "Aurora Global Database physical replication lag from ${local.primary_region} to ${local.secondary_region} exceeded ${var.replication_lag_alarm_threshold_ms}ms"
  treat_missing_data  = "breaching"

  dimensions = {
    DBClusterIdentifier = aws_rds_cluster.secondary[0].cluster_identifier
  }
}
