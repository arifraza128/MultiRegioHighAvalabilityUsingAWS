# =============================================================================
# Root Module: Multi-Region High Availability & Disaster Recovery (AWS)
# Primary Region: var.primary_region (aws.primary)
# Secondary Region: var.secondary_region (aws.secondary)
# =============================================================================

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
  name_prefix = "${var.project_name}-${var.environment}"
}

# -----------------------------------------------------------------------------
# Phase 2: Primary Region Network & ECS Application Stack (us-east-1)
# -----------------------------------------------------------------------------
module "network_primary" {
  source = "./modules/network"
  providers = {
    aws = aws.primary
  }

  project_name       = var.project_name
  environment        = var.environment
  vpc_cidr           = var.primary_vpc_cidr
  single_nat_gateway = var.single_nat_gateway
}

module "ecs_primary" {
  source = "./modules/ecs"
  providers = {
    aws = aws.primary
  }

  project_name                       = var.project_name
  environment                        = var.environment
  vpc_id                             = module.network_primary.vpc_id
  public_subnet_ids                  = module.network_primary.public_subnet_ids
  private_app_subnet_ids             = module.network_primary.private_app_subnet_ids
  logs_kms_key_arn                   = module.network_primary.logs_kms_key_arn
  desired_count                      = var.primary_desired_count
  is_primary_region                  = true
  ecr_replication_destination_region = var.enable_secondary_region ? data.aws_region.secondary.name : ""

  # Phase 4: Wired automatically when enable_aurora_global = true
  db_host        = var.enable_aurora_global ? module.aurora_global[0].primary_cluster_endpoint : ""
  db_secret_arn  = var.enable_aurora_global ? module.aurora_global[0].primary_secret_arn : ""
  db_kms_key_arn = var.enable_aurora_global ? module.aurora_global[0].primary_kms_key_arn : ""
}

# -----------------------------------------------------------------------------
# Phase 3: Secondary Region Warm Standby Network & ECS Stack (ap-south-1)
# Instantiates the EXACT same modules using aws.secondary provider alias!
# -----------------------------------------------------------------------------
module "network_secondary" {
  count  = var.enable_secondary_region ? 1 : 0
  source = "./modules/network"
  providers = {
    aws = aws.secondary
  }

  project_name       = var.project_name
  environment        = var.environment
  vpc_cidr           = var.secondary_vpc_cidr
  single_nat_gateway = var.single_nat_gateway
}

module "ecs_secondary" {
  count  = var.enable_secondary_region ? 1 : 0
  source = "./modules/ecs"
  providers = {
    aws = aws.secondary
  }

  project_name           = var.project_name
  environment            = var.environment
  vpc_id                 = module.network_secondary[0].vpc_id
  public_subnet_ids      = module.network_secondary[0].public_subnet_ids
  private_app_subnet_ids = module.network_secondary[0].private_app_subnet_ids
  logs_kms_key_arn       = module.network_secondary[0].logs_kms_key_arn
  desired_count          = var.secondary_desired_count
  is_primary_region      = false

  # Phase 4: Wired automatically when enable_aurora_global = true
  db_host        = var.enable_aurora_global ? module.aurora_global[0].secondary_cluster_endpoint : ""
  db_secret_arn  = var.enable_aurora_global ? module.aurora_global[0].secondary_secret_arn : ""
  db_kms_key_arn = var.enable_aurora_global ? module.aurora_global[0].secondary_kms_key_arn : ""
}

# -----------------------------------------------------------------------------
# Phase 4: Aurora Global Database (PostgreSQL Serverless v2) & Secret Replication
# -----------------------------------------------------------------------------
module "aurora_global" {
  count  = var.enable_aurora_global ? 1 : 0
  source = "./modules/aurora"
  providers = {
    aws.primary   = aws.primary
    aws.secondary = aws.secondary
  }

  project_name                    = var.project_name
  environment                     = var.environment
  enable_secondary_region         = var.enable_secondary_region
  primary_vpc_id                  = module.network_primary.vpc_id
  primary_db_subnet_ids           = module.network_primary.isolated_db_subnet_ids
  primary_ecs_security_group_id   = module.ecs_primary.ecs_tasks_security_group_id
  secondary_vpc_id                = var.enable_secondary_region ? module.network_secondary[0].vpc_id : ""
  secondary_db_subnet_ids         = var.enable_secondary_region ? module.network_secondary[0].isolated_db_subnet_ids : []
  secondary_ecs_security_group_id = var.enable_secondary_region ? module.ecs_secondary[0].ecs_tasks_security_group_id : ""
}
