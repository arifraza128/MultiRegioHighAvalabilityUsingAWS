data "aws_region" "current" {}
data "aws_caller_identity" "current" {}

data "aws_availability_zones" "available" {
  state = "available"
}

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

  azs        = slice(data.aws_availability_zones.available.names, 0, var.az_count)
  nat_count  = var.single_nat_gateway ? 1 : var.az_count
  account_id = data.aws_caller_identity.current.account_id
}

# -----------------------------------------------------------------------------
# 1. Customer-Managed KMS Key for Regional Logs & Network Encryption
# -----------------------------------------------------------------------------
resource "aws_kms_key" "network_logs" {
  description             = "KMS key for VPC Flow Logs and regional observability in ${local.region_name}"
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
      },
      {
        Sid    = "AllowCloudWatchLogsEncryption"
        Effect = "Allow"
        Principal = {
          Service = "logs.${local.region_name}.amazonaws.com"
        }
        Action = [
          "kms:Encrypt*",
          "kms:Decrypt*",
          "kms:ReEncrypt*",
          "kms:GenerateDataKey*",
          "kms:Describe*"
        ]
        Resource = "*"
        Condition = {
          ArnLike = {
            "kms:EncryptionContext:aws:logs:arn" = "arn:aws:logs:${local.region_name}:${local.account_id}:log-group:*"
          }
        }
      }
    ]
  })
}

resource "aws_kms_alias" "network_logs" {
  name          = "alias/${local.name_prefix}-network-logs"
  target_key_id = aws_kms_key.network_logs.key_id
}

# -----------------------------------------------------------------------------
# 2. VPC & Default Security Group Lockdown (Checkov CKV2_AWS_11 & CKV2_AWS_12)
# -----------------------------------------------------------------------------
resource "aws_vpc" "this" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "${local.name_prefix}-vpc"
  }
}

resource "aws_default_security_group" "default" {
  vpc_id = aws_vpc.this.id

  tags = {
    Name = "${local.name_prefix}-default-sg-restricted"
  }
}

# -----------------------------------------------------------------------------
# 3. Subnets: Public (ALB/NAT), Private App (ECS Fargate), Isolated DB (Aurora)
#    Public:      10.x.1.0/24, 10.x.2.0/24
#    Private App: 10.x.11.0/24, 10.x.12.0/24
#    Isolated DB: 10.x.21.0/24, 10.x.22.0/24
# -----------------------------------------------------------------------------
resource "aws_subnet" "public" {
  count                   = var.az_count
  vpc_id                  = aws_vpc.this.id
  cidr_block              = cidrsubnet(var.vpc_cidr, 8, count.index + 1)
  availability_zone       = local.azs[count.index]
  map_public_ip_on_launch = false

  tags = {
    Name = "${local.name_prefix}-public-${local.azs[count.index]}"
    Tier = "public"
  }
}

resource "aws_subnet" "private_app" {
  count                   = var.az_count
  vpc_id                  = aws_vpc.this.id
  cidr_block              = cidrsubnet(var.vpc_cidr, 8, count.index + 11)
  availability_zone       = local.azs[count.index]
  map_public_ip_on_launch = false

  tags = {
    Name = "${local.name_prefix}-private-app-${local.azs[count.index]}"
    Tier = "private-app"
  }
}

resource "aws_subnet" "isolated_db" {
  count                   = var.az_count
  vpc_id                  = aws_vpc.this.id
  cidr_block              = cidrsubnet(var.vpc_cidr, 8, count.index + 21)
  availability_zone       = local.azs[count.index]
  map_public_ip_on_launch = false

  tags = {
    Name = "${local.name_prefix}-isolated-db-${local.azs[count.index]}"
    Tier = "isolated-db"
  }
}

# -----------------------------------------------------------------------------
# 4. Internet Gateway, Elastic IP & NAT Gateway
# -----------------------------------------------------------------------------
resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id

  tags = {
    Name = "${local.name_prefix}-igw"
  }
}

resource "aws_eip" "nat" {
  count  = local.nat_count
  domain = "vpc"

  tags = {
    Name = "${local.name_prefix}-nat-eip-${count.index + 1}"
  }

  depends_on = [aws_internet_gateway.this]
}

resource "aws_nat_gateway" "this" {
  count         = local.nat_count
  allocation_id = aws_eip.nat[count.index].id
  subnet_id     = aws_subnet.public[count.index].id

  tags = {
    Name = "${local.name_prefix}-nat-${count.index + 1}"
  }

  depends_on = [aws_internet_gateway.this]
}

# -----------------------------------------------------------------------------
# 5. Route Tables (Public, Private App, Isolated DB)
# -----------------------------------------------------------------------------
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.this.id
  }

  tags = {
    Name = "${local.name_prefix}-public-rt"
  }
}

resource "aws_route_table_association" "public" {
  count          = var.az_count
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table" "private_app" {
  count  = var.az_count
  vpc_id = aws_vpc.this.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.this[var.single_nat_gateway ? 0 : count.index].id
  }

  tags = {
    Name = "${local.name_prefix}-private-app-rt-${count.index + 1}"
  }
}

resource "aws_route_table_association" "private_app" {
  count          = var.az_count
  subnet_id      = aws_subnet.private_app[count.index].id
  route_table_id = aws_route_table.private_app[count.index].id
}

resource "aws_route_table" "isolated_db" {
  vpc_id = aws_vpc.this.id

  tags = {
    Name = "${local.name_prefix}-isolated-db-rt"
  }
}

resource "aws_route_table_association" "isolated_db" {
  count          = var.az_count
  subnet_id      = aws_subnet.isolated_db[count.index].id
  route_table_id = aws_route_table.isolated_db.id
}

# -----------------------------------------------------------------------------
# 6. VPC Flow Logs to KMS-Encrypted CloudWatch Log Group
# -----------------------------------------------------------------------------
resource "aws_cloudwatch_log_group" "flow_logs" {
  name              = "/aws/vpc-flow-logs/${local.name_prefix}"
  retention_in_days = var.flow_log_retention_days
  kms_key_id        = aws_kms_key.network_logs.arn
}

resource "aws_iam_role" "flow_logs" {
  name = "${local.name_prefix}-vpc-flow-logs-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "vpc-flow-logs.amazonaws.com"
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

resource "aws_iam_role_policy" "flow_logs" {
  name = "${local.name_prefix}-vpc-flow-logs-policy"
  role = aws_iam_role.flow_logs.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogStream",
          "logs:PutLogEvents",
          "logs:DescribeLogGroups",
          "logs:DescribeLogStreams"
        ]
        Resource = "${aws_cloudwatch_log_group.flow_logs.arn}:*"
      }
    ]
  })
}

resource "aws_flow_log" "this" {
  vpc_id               = aws_vpc.this.id
  traffic_type         = "ALL"
  log_destination_type = "cloud-watch-logs"
  log_destination      = aws_cloudwatch_log_group.flow_logs.arn
  iam_role_arn         = aws_iam_role.flow_logs.arn

  tags = {
    Name = "${local.name_prefix}-vpc-flow-log"
  }
}
