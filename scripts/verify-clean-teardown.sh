#!/usr/bin/env bash
# =============================================================================
# Post-Session Teardown Verification Script
# Verifies zero lingering high-cost resources across Primary & Secondary regions
# =============================================================================
set -euo pipefail

PRIMARY_REGION="${1:-us-east-1}"
SECONDARY_REGION="${2:-ap-south-1}"
PROJECT_TAG="${3:-ha-notes}"

echo "=== Auditing lingering billable resources for Project=${PROJECT_TAG} ==="

for REGION in "$PRIMARY_REGION" "$SECONDARY_REGION"; do
  echo ""
  echo "--- Checking Region: ${REGION} ---"

  echo "[1/5] Checking NAT Gateways ( non-deleted )..."
  aws ec2 describe-nat-gateways --region "$REGION" \
    --filter "Name=tag:Project,Values=${PROJECT_TAG}" "Name=state,Values=pending,available" \
    --query "NatGateways[].{ID:NatGatewayId,State:State}" --output table

  echo "[2/5] Checking Application Load Balancers..."
  aws elbv2 describe-load-balancers --region "$REGION" \
    --query "LoadBalancers[?contains(LoadBalancerName, '${PROJECT_TAG}')].{Name:LoadBalancerName,DNS:DNSName}" --output table

  echo "[3/5] Checking ECS Clusters & Running Tasks..."
  aws ecs list-clusters --region "$REGION" \
    --query "clusterArns[?contains(@, '${PROJECT_TAG}')]" --output table

  echo "[4/5] Checking RDS / Aurora Instances..."
  aws rds describe-db-instances --region "$REGION" \
    --query "DBInstances[?contains(DBInstanceIdentifier, '${PROJECT_TAG}')].{ID:DBInstanceIdentifier,Status:DBInstanceStatus,Class:DBInstanceClass}" --output table

  echo "[5/5] Checking Unattached Elastic IPs..."
  aws ec2 describe-addresses --region "$REGION" \
    --filters "Name=tag:Project,Values=${PROJECT_TAG}" \
    --query "Addresses[].{PublicIp:PublicIp,AllocationId:AllocationId}" --output table
done

echo ""
echo "--- Checking Global Route 53 ARC Clusters ($2.50/hr!) ---"
aws route53-recovery-control-config list-clusters --region us-west-2 \
  --query "Clusters[?contains(Name, '${PROJECT_TAG}')].{Name:Name,Status:Status,ClusterArn:ClusterArn}" --output table

echo ""
echo "=== Teardown Audit Complete ==="
