#!/usr/bin/env bash
# =============================================================================
# Aurora Global Database Replication Lag Measurement Script (Prompt 10)
# Queries CloudWatch in ap-south-1 for AuroraGlobalDBReplicationLag (ms)
# =============================================================================
set -euo pipefail

SECONDARY_REGION="${1:-ap-south-1}"
SECONDARY_CLUSTER_ID="${2:-ha-notes-dev-aps1-aurora-cluster}"
MINUTES="${3:-15}"

END_TIME=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
START_TIME=$(date -u -d "${MINUTES} minutes ago" +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || date -u -v-"${MINUTES}"M +"%Y-%m-%dT%H:%M:%SZ")

echo "=== Querying AuroraGlobalDBReplicationLag for ${SECONDARY_CLUSTER_ID} in ${SECONDARY_REGION} ==="
echo "Window: ${START_TIME} -> ${END_TIME}"

aws cloudwatch get-metric-statistics \
  --region "$SECONDARY_REGION" \
  --namespace "AWS/RDS" \
  --metric-name "AuroraGlobalDBReplicationLag" \
  --dimensions Name=DBClusterIdentifier,Value="$SECONDARY_CLUSTER_ID" \
  --start-time "$START_TIME" \
  --end-time "$END_TIME" \
  --period 60 \
  --statistics Minimum Average Maximum \
  --query "sort_by(Datapoints, &Timestamp)[].{Time:Timestamp,Min_ms:Minimum,Avg_ms:Average,Max_ms:Maximum}" \
  --output table
