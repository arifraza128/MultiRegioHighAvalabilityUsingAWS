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

  # Shared ECR repository name across primary & secondary so ECR Cross-Region Replication maps 1:1
  ecr_repo_name = "${var.project_name}-${var.environment}-api"
  has_db_secret = var.db_secret_arn != ""
}

# -----------------------------------------------------------------------------
# 1. Amazon ECR Repository + Cross-Region Replication (Primary -> Secondary)
# -----------------------------------------------------------------------------
resource "aws_ecr_repository" "app" {
  name                 = local.ecr_repo_name
  image_tag_mutability = "IMMUTABLE"
  force_delete         = true

  image_scanning_configuration {
    scan_on_push = true
  }

  encryption_configuration {
    encryption_type = "KMS"
    kms_key         = var.logs_kms_key_arn
  }

  tags = {
    Name = "${local.name_prefix}-ecr"
  }
}

resource "aws_ecr_lifecycle_policy" "app" {
  repository = aws_ecr_repository.app.name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Keep last 10 images to control ECR storage costs"
        selection = {
          tagStatus   = "any"
          countType   = "imageCountMoreThan"
          countNumber = 10
        }
        action = {
          type = "expire"
        }
      }
    ]
  })
}

resource "aws_ecr_replication_configuration" "cross_region" {
  count = var.is_primary_region && var.ecr_replication_destination_region != "" ? 1 : 0

  replication_configuration {
    rule {
      destination {
        region      = var.ecr_replication_destination_region
        registry_id = local.account_id
      }

      repository_filter {
        filter      = local.ecr_repo_name
        filter_type = "PREFIX_MATCH"
      }
    }
  }
}

# -----------------------------------------------------------------------------
# 2. Security Groups: Public ALB & Private ECS Fargate Tasks
# -----------------------------------------------------------------------------
resource "aws_security_group" "alb" {
  name        = "${local.name_prefix}-alb-sg"
  description = "Public ALB security group in ${local.region_name}"
  vpc_id      = var.vpc_id

  tags = {
    Name = "${local.name_prefix}-alb-sg"
  }
}

resource "aws_vpc_security_group_ingress_rule" "alb_http" {
  security_group_id = aws_security_group.alb.id
  description       = "Allow public HTTP ingress to ALB"
  cidr_ipv4         = "0.0.0.0/0"
  from_port         = 80
  to_port           = 80
  ip_protocol       = "tcp"
}

resource "aws_security_group" "ecs_tasks" {
  name        = "${local.name_prefix}-ecs-tasks-sg"
  description = "Private ECS Fargate tasks security group in ${local.region_name}"
  vpc_id      = var.vpc_id

  tags = {
    Name = "${local.name_prefix}-ecs-tasks-sg"
  }
}

resource "aws_vpc_security_group_egress_rule" "alb_to_ecs" {
  security_group_id            = aws_security_group.alb.id
  description                  = "Allow ALB outbound traffic strictly to ECS tasks on container port"
  referenced_security_group_id = aws_security_group.ecs_tasks.id
  from_port                    = var.container_port
  to_port                      = var.container_port
  ip_protocol                  = "tcp"
}

resource "aws_vpc_security_group_ingress_rule" "ecs_from_alb" {
  security_group_id            = aws_security_group.ecs_tasks.id
  description                  = "Allow inbound traffic strictly from the regional ALB"
  referenced_security_group_id = aws_security_group.alb.id
  from_port                    = var.container_port
  to_port                      = var.container_port
  ip_protocol                  = "tcp"
}

resource "aws_vpc_security_group_egress_rule" "ecs_https_out" {
  security_group_id = aws_security_group.ecs_tasks.id
  description       = "Allow outbound HTTPS to ECR, Secrets Manager, and CloudWatch via NAT"
  cidr_ipv4         = "0.0.0.0/0"
  from_port         = 443
  to_port           = 443
  ip_protocol       = "tcp"
}

resource "aws_vpc_security_group_egress_rule" "ecs_postgres_out" {
  security_group_id = aws_security_group.ecs_tasks.id
  description       = "Allow outbound PostgreSQL to regional VPC CIDR"
  cidr_ipv4         = "10.0.0.0/8"
  from_port         = var.db_port
  to_port           = var.db_port
  ip_protocol       = "tcp"
}

# -----------------------------------------------------------------------------
# 3. Application Load Balancer & Target Group (/health/deep)
# -----------------------------------------------------------------------------
resource "aws_lb" "this" {
  name                       = "${local.name_prefix}-alb"
  internal                   = false
  load_balancer_type         = "application"
  security_groups            = [aws_security_group.alb.id]
  subnets                    = var.public_subnet_ids
  drop_invalid_header_fields = true
  enable_deletion_protection = false

  tags = {
    Name = "${local.name_prefix}-alb"
  }
}

resource "aws_lb_target_group" "app" {
  name                 = "${local.name_prefix}-tg"
  port                 = var.container_port
  protocol             = "HTTP"
  vpc_id               = var.vpc_id
  target_type          = "ip"
  deregistration_delay = 15

  health_check {
    enabled             = true
    path                = "/health/deep"
    protocol            = "HTTP"
    matcher             = "200"
    interval            = 15
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 2
  }

  tags = {
    Name = "${local.name_prefix}-tg"
  }
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.this.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app.arn
  }
}

# -----------------------------------------------------------------------------
# 4. KMS-Encrypted CloudWatch Log Group & ECS Cluster
# -----------------------------------------------------------------------------
resource "aws_cloudwatch_log_group" "ecs" {
  name              = "/ecs/${local.name_prefix}-api"
  retention_in_days = var.log_retention_days
  kms_key_id        = var.logs_kms_key_arn
}

resource "aws_ecs_cluster" "this" {
  name = "${local.name_prefix}-cluster"

  setting {
    name  = "containerInsights"
    value = "enabled"
  }

  tags = {
    Name = "${local.name_prefix}-cluster"
  }
}

# -----------------------------------------------------------------------------
# 5. Least-Privilege IAM Roles (Task Execution Role vs. Runtime Task Role)
# -----------------------------------------------------------------------------
data "aws_iam_policy_document" "ecs_assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [local.account_id]
    }
  }
}

resource "aws_iam_role" "execution" {
  name               = "${local.name_prefix}-ecs-exec-role"
  assume_role_policy = data.aws_iam_policy_document.ecs_assume_role.json
}

resource "aws_iam_role_policy" "execution" {
  name = "${local.name_prefix}-ecs-exec-policy"
  role = aws_iam_role.execution.id

  # checkov:skip=CKV_AWS_355:ecr:GetAuthorizationToken is an AWS account-level call that does not support resource-level ARN restrictions.
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = concat(
      [
        {
          Sid      = "AllowECRAuthorizationToken"
          Effect   = "Allow"
          Action   = ["ecr:GetAuthorizationToken"]
          Resource = "*"
        },
        {
          Sid    = "AllowRegionalECRPull"
          Effect = "Allow"
          Action = [
            "ecr:BatchCheckLayerAvailability",
            "ecr:GetDownloadUrlForLayer",
            "ecr:BatchGetImage"
          ]
          Resource = aws_ecr_repository.app.arn
        },
        {
          Sid    = "AllowCloudWatchLogStreamWrite"
          Effect = "Allow"
          Action = [
            "logs:CreateLogStream",
            "logs:PutLogEvents"
          ]
          Resource = "${aws_cloudwatch_log_group.ecs.arn}:*"
        },
        {
          Sid    = "AllowKMSDecryptForECRAndLogs"
          Effect = "Allow"
          Action = [
            "kms:Decrypt",
            "kms:DescribeKey"
          ]
          Resource = compact([var.logs_kms_key_arn, var.db_kms_key_arn])
        }
      ],
      local.has_db_secret ? [
        {
          Sid    = "AllowReadSpecificDatabaseSecret"
          Effect = "Allow"
          Action = [
            "secretsmanager:GetSecretValue",
            "secretsmanager:DescribeSecret"
          ]
          Resource = var.db_secret_arn
        }
      ] : []
    )
  })
}

resource "aws_iam_role" "task" {
  name               = "${local.name_prefix}-ecs-task-role"
  assume_role_policy = data.aws_iam_policy_document.ecs_assume_role.json
}

resource "aws_iam_role_policy" "task" {
  name = "${local.name_prefix}-ecs-task-policy"
  role = aws_iam_role.task.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowEmitCustomApplicationMetrics"
        Effect = "Allow"
        Action = [
          "cloudwatch:PutMetricData"
        ]
        Resource = "*"
        Condition = {
          StringEquals = {
            "cloudwatch:namespace" = "${var.project_name}/${var.environment}"
          }
        }
      }
    ]
  })
}

# -----------------------------------------------------------------------------
# 6. ECS Fargate Task Definition & Service
# -----------------------------------------------------------------------------
resource "aws_ecs_task_definition" "app" {
  family                   = "${local.name_prefix}-api"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = tostring(var.task_cpu)
  memory                   = tostring(var.task_memory)
  execution_role_arn       = aws_iam_role.execution.arn
  task_role_arn            = aws_iam_role.task.arn

  container_definitions = jsonencode([
    {
      name      = "notes-api"
      image     = "${aws_ecr_repository.app.repository_url}:${var.image_tag}"
      essential = true

      portMappings = [
        {
          containerPort = var.container_port
          hostPort      = var.container_port
          protocol      = "tcp"
        }
      ]

      environment = [
        { name = "PORT", value = tostring(var.container_port) },
        { name = "AWS_REGION", value = local.region_name },
        { name = "DB_HOST", value = var.db_host },
        { name = "DB_PORT", value = tostring(var.db_port) },
        { name = "DB_NAME", value = var.db_name },
        { name = "DB_SSL", value = "true" }
      ]

      secrets = local.has_db_secret ? [
        {
          name      = "DB_USER"
          valueFrom = "${var.db_secret_arn}:username::"
        },
        {
          name      = "DB_PASSWORD"
          valueFrom = "${var.db_secret_arn}:password::"
        }
      ] : []

      healthCheck = {
        command     = ["CMD-SHELL", "wget --no-verbose --tries=1 --spider http://localhost:${var.container_port}/health || exit 1"]
        interval    = 30
        timeout     = 5
        retries     = 3
        startPeriod = 15
      }

      readonlyRootFilesystem = true

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.ecs.name
          "awslogs-region"        = local.region_name
          "awslogs-stream-prefix" = "ecs"
        }
      }
    }
  ])
}

resource "aws_ecs_service" "app" {
  name                              = "${local.name_prefix}-service"
  cluster                           = aws_ecs_cluster.this.id
  task_definition                   = aws_ecs_task_definition.app.arn
  desired_count                     = var.desired_count
  launch_type                       = "FARGATE"
  health_check_grace_period_seconds = 30

  deployment_circuit_breaker {
    enable   = true
    rollback = true
  }

  network_configuration {
    subnets          = var.private_app_subnet_ids
    security_groups  = [aws_security_group.ecs_tasks.id]
    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.app.arn
    container_name   = "notes-api"
    container_port   = var.container_port
  }

  depends_on = [aws_lb_listener.http]
}
