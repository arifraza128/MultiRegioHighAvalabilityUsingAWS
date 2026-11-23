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

# NOTE: Per Prompt 8 rules ("No application resources yet"), module invocations
# will be added incrementally starting in Prompt 9 (modules/network, modules/ecs, etc.).
