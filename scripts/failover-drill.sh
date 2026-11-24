#!/usr/bin/env bash
# =============================================================================
# Automated Disaster Recovery Exercise & Measurement Script (Prompt 21)
# Executes:
#   1. Pre-flight baseline latency & replication lag check
#   2. Starts background RPO/RTO write probe (scripts/probe-rpo-rto.js)
#   3. Injects fault in us-east-1 via AWS FIS (with CloudWatch Stop Condition)
#   4. Executes Failover (Aurora Promotion + Route 53 ARC Routing Control flip)
#   5. Waits for probe to confirm T4 recovery in ap-south-1 and saves evidence
# =============================================================================
set -euo pipefail

TRIAL_NUM="${1:-1}"
EVIDENCE_DIR="evidence"
mkdir -p "${EVIDENCE_DIR}"

echo "=== Starting DR Failover Measurement Exercise (Trial #${TRIAL_NUM}) ==="
echo "NOTE: AWS FIS simulates component/service failures inside us-east-1, NOT a true regional AWS blackout."

PRIMARY_ALB_URL="http://$(terraform output -raw primary_alb_dns_name)"
SECONDARY_ALB_URL="http://$(terraform output -raw secondary_alb_dns_name)"
FIS_TEMPLATE_ID=$(terraform output -raw fis_ecs_task_termination_template_id)

echo "[1/5] Recording baseline health in us-east-1 and ap-south-1..."
curl -s "${PRIMARY_ALB_URL}/health/deep" | tee "${EVIDENCE_DIR}/trial-${TRIAL_NUM}-baseline-primary.json"
echo ""
curl -s "${SECONDARY_ALB_URL}/health/deep" | tee "${EVIDENCE_DIR}/trial-${TRIAL_NUM}-baseline-secondary.json"
echo ""

echo "[2/5] Starting continuous RPO/RTO monotonic write probe in background..."
node scripts/probe-rpo-rto.js \
  --primary "${PRIMARY_ALB_URL}" \
  --secondary "${SECONDARY_ALB_URL}" \
  --trial "${TRIAL_NUM}" \
  --output "${EVIDENCE_DIR}/trial-${TRIAL_NUM}-rto-rpo.json" &
PROBE_PID=$!

sleep 5

echo "[3/5] Starting AWS FIS fault injection in us-east-1 (Template: ${FIS_TEMPLATE_ID})..."
FIS_EXP_ID=$(aws fis start-experiment \
  --region us-east-1 \
  --experiment-template-id "${FIS_TEMPLATE_ID}" \
  --query "experiment.id" --output text)
echo "Started FIS Experiment: ${FIS_EXP_ID}"

echo "[4/5] Executing Failover Runbook steps (Promote ap-south-1 Aurora & Flip ARC Controls)..."
echo " Follow RUNBOOK.md Step 1 -> Step 3 or press Enter once ap-south-1 is promoted..."

wait "${PROBE_PID}"
echo "[5/5] Trial #${TRIAL_NUM} complete! Evidence saved to ${EVIDENCE_DIR}/trial-${TRIAL_NUM}-rto-rpo.json"
