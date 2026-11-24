# =============================================================================
# Route 53 Application Recovery Controller (ARC)
# - ARC Cluster (5 globally distributed data-plane endpoints — $2.50/hr while active)
# - Control Panel + 2 Routing Controls (Primary us-east-1, Secondary ap-south-1)
# - Assertion Safety Rule: ATLEAST 1 routing control must remain ON
#   (mathematically prevents turning both regions OFF simultaneously!)
# - Route 53 Health Checks bound to ARC Routing Controls + DNS Failover Records
# =============================================================================

locals {
  name_prefix       = "${var.project_name}-${var.environment}"
  has_secondary_alb = var.secondary_alb_dns_name != "" && var.secondary_alb_zone_id != ""
}

# -----------------------------------------------------------------------------
# 1. Route 53 ARC Cluster & Control Panel
# -----------------------------------------------------------------------------
resource "aws_route53recoverycontrolconfig_cluster" "this" {
  name = "${local.name_prefix}-arc-cluster"
}

resource "aws_route53recoverycontrolconfig_control_panel" "this" {
  name        = "${local.name_prefix}-control-panel"
  cluster_arn = aws_route53recoverycontrolconfig_cluster.this.arn
}

# -----------------------------------------------------------------------------
# 2. Routing Controls (Primary & Secondary)
# -----------------------------------------------------------------------------
resource "aws_route53recoverycontrolconfig_routing_control" "primary" {
  name              = "${local.name_prefix}-rc-${var.primary_region}"
  cluster_arn       = aws_route53recoverycontrolconfig_cluster.this.arn
  control_panel_arn = aws_route53recoverycontrolconfig_control_panel.this.arn
}

resource "aws_route53recoverycontrolconfig_routing_control" "secondary" {
  name              = "${local.name_prefix}-rc-${var.secondary_region}"
  cluster_arn       = aws_route53recoverycontrolconfig_cluster.this.arn
  control_panel_arn = aws_route53recoverycontrolconfig_control_panel.this.arn
}

# -----------------------------------------------------------------------------
# 3. ARC Assertion Safety Rule: Both Controls NEVER OFF Together
#    Enforces Make-Before-Break failover: [ON, OFF] -> [ON, ON] -> [OFF, ON]
# -----------------------------------------------------------------------------
resource "aws_route53recoverycontrolconfig_safety_rule" "at_least_one_active" {
  name              = "${local.name_prefix}-never-both-off-rule"
  control_panel_arn = aws_route53recoverycontrolconfig_control_panel.this.arn
  wait_period_ms    = 5000

  asserted_controls = [
    aws_route53recoverycontrolconfig_routing_control.primary.arn,
    aws_route53recoverycontrolconfig_routing_control.secondary.arn
  ]

  rule_config {
    inverted  = false
    threshold = 1
    type      = "ATLEAST"
  }
}

# -----------------------------------------------------------------------------
# 4. Route 53 Health Checks Linked to ARC Routing Controls
# -----------------------------------------------------------------------------
resource "aws_route53_health_check" "primary_arc" {
  type                = "RECOVERY_CONTROL"
  routing_control_arn = aws_route53recoverycontrolconfig_routing_control.primary.arn

  tags = {
    Name = "${local.name_prefix}-hc-arc-${var.primary_region}"
  }
}

resource "aws_route53_health_check" "secondary_arc" {
  type                = "RECOVERY_CONTROL"
  routing_control_arn = aws_route53recoverycontrolconfig_routing_control.secondary.arn

  tags = {
    Name = "${local.name_prefix}-hc-arc-${var.secondary_region}"
  }
}

# -----------------------------------------------------------------------------
# 5. Route 53 Hosted Zone & ARC-Controlled Active/Standby Alias Records
# -----------------------------------------------------------------------------
resource "aws_route53_zone" "this" {
  name    = var.domain_name
  comment = "Multi-Region HA Failover Zone controlled by Route 53 ARC"

  vpc {
    vpc_id     = var.primary_vpc_id
    vpc_region = var.primary_region
  }

  dynamic "vpc" {
    for_each = var.secondary_vpc_id != "" ? [1] : []
    content {
      vpc_id     = var.secondary_vpc_id
      vpc_region = var.secondary_region
    }
  }
}

resource "aws_route53_record" "api_primary" {
  zone_id         = aws_route53_zone.this.zone_id
  name            = "api.${var.domain_name}"
  type            = "A"
  set_identifier  = "primary-${var.primary_region}"
  health_check_id = aws_route53_health_check.primary_arc.id

  failover_routing_policy {
    type = "PRIMARY"
  }

  alias {
    name                   = var.primary_alb_dns_name
    zone_id                = var.primary_alb_zone_id
    evaluate_target_health = true
  }
}

resource "aws_route53_record" "api_secondary" {
  count           = local.has_secondary_alb ? 1 : 0
  zone_id         = aws_route53_zone.this.zone_id
  name            = "api.${var.domain_name}"
  type            = "A"
  set_identifier  = "secondary-${var.secondary_region}"
  health_check_id = aws_route53_health_check.secondary_arc.id

  failover_routing_policy {
    type = "SECONDARY"
  }

  alias {
    name                   = var.secondary_alb_dns_name
    zone_id                = var.secondary_alb_zone_id
    evaluate_target_health = true
  }
}
