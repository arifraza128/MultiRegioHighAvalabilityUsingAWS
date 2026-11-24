# Disaster Recovery Runbook: Unplanned Regional Failover (`RUNBOOK.md`)

**Sources of Truth:** [DESIGN.md](file:///c:/Users/arif3/OneDrive/Attachments/Desktop/MultiRegioHighAvalabilityUsingAWS/DESIGN.md), [ARCHITECTURE.md](file:///c:/Users/arif3/OneDrive/Attachments/Desktop/MultiRegioHighAvalabilityUsingAWS/ARCHITECTURE.md), [DATABASE.md](file:///c:/Users/arif3/OneDrive/Attachments/Desktop/MultiRegioHighAvalabilityUsingAWS/DATABASE.md), [API.md](file:///c:/Users/arif3/OneDrive/Attachments/Desktop/MultiRegioHighAvalabilityUsingAWS/API.md)  
**Scenario:** Catastrophic Primary Region (`us-east-1`) Impairment -> Unplanned Failover to Warm Standby (`ap-south-1`)  
**Target RTO Hypothesis:** `< 180 seconds` | **Target RPO Hypothesis:** `< 2 seconds`  
**Required Tools:** `aws-cli >= 2.15`, `jq`, `curl`, `node >= 20`

---

## 0. Architectural Honesty & Pre-Execution Warning

> [!IMPORTANT]
> 1. **Destructive One-Way Database Action:** Step 3 (`failover-global-cluster --allow-data-loss` or `remove-from-global-cluster`) promotes `ap-south-1` Aurora to a standalone/primary Writer. Never execute this for a single-task crash or single-AZ blip that Multi-AZ handles automatically.
> 2. **FIS Chaos Testing Boundary:** When triggering this runbook during an AWS Fault Injection Service (FIS) drill, note that FIS simulates component/service failures inside `us-east-1`, **not** a genuine AWS global control-plane blackout.

---

## 1. Environment Variables Setup

Export the dynamic values from Terraform outputs before starting the clock (or keep a pre-exported `env.sh` saved in an external location so you do not depend on `us-east-1` during a real incident):

```bash
export PRIMARY_REGION="us-east-1"
export SECONDARY_REGION="ap-south-1"
export GLOBAL_CLUSTER_ID=$(terraform output -raw aurora_global_cluster_id)
export SECONDARY_CLUSTER_ARN="arn:aws:rds:${SECONDARY_REGION}:$(terraform output -raw account_id):cluster:ha-notes-dev-aps1-aurora-cluster"
export SECONDARY_ECS_CLUSTER="ha-notes-dev-aps1-cluster"
export SECONDARY_ECS_SERVICE="ha-notes-dev-aps1-service"
export PRIMARY_ALB_URL="http://$(terraform output -raw primary_alb_dns_name)"
export SECONDARY_ALB_URL="http://$(terraform output -raw secondary_alb_dns_name)"

# Route 53 ARC Data-Plane Routing Control ARNs & Surviving Endpoint (e.g., ap-northeast-1 or eu-west-1)
export ARC_PRIMARY_CONTROL_ARN=$(terraform output -raw arc_primary_routing_control_arn)
export ARC_SECONDARY_CONTROL_ARN=$(terraform output -raw arc_secondary_routing_control_arn)
export ARC_CLUSTER_ENDPOINT=$(terraform output -json arc_cluster_endpoints | jq -r '.[] | select(.region=="eu-west-1") | .endpoint')
export ARC_ENDPOINT_REGION="eu-west-1"
```

---

## 2. Preconditions Checklist (Execute Before Promoting!)

Verify that `us-east-1` is genuinely impaired and that `ap-south-1` warm standby is healthy and ready to accept traffic.

### 2.1 Confirm Primary (`us-east-1`) Impairment & Record `T0` / `T1`
```bash
echo "T1_DETECTION_UTC=$(date -u +"%Y-%m-%dT%H:%M:%S.%3NZ")"
curl -i --max-time 3 "${PRIMARY_ALB_URL}/health/deep"
```
- **Expected Failing State:** Connection timeout or `HTTP/1.1 503 Service Unavailable`, and CloudWatch Alarm `ha-notes-dev-use1-alb-no-healthy-hosts` in `ALARM` state.

### 2.2 Confirm Secondary (`ap-south-1`) Warm Standby Health & Pre-Outage Replication Lag
```bash
# 1. Verify warm standby Fargate task is running and connected to local replica
curl -s "${SECONDARY_ALB_URL}/health/deep" | jq .

# 2. Check recent AuroraGlobalDBReplicationLag in ap-south-1
bash scripts/measure-replication-lag.sh "${SECONDARY_REGION}" "ha-notes-dev-aps1-aurora-cluster" 10
```
- **Expected Output:**
  - `GET /health/deep` in `ap-south-1` returns `HTTP 200` with `"status": "healthy"`, `"db_reachable": true`, `"db_role": "replica"`.
  - Pre-outage `AuroraGlobalDBReplicationLag` was `< 5000 ms` (typically `200–800 ms`).

---

## 3. Step-by-Step Failover Execution

### Step 1: Scale Up Secondary ECS Fargate Service (`1 -> 2` Tasks) [`T2`]
*Expected Duration: 5 seconds to trigger (runs asynchronously in background while DB promotes; warm standby task #1 can already serve traffic immediately).*

```bash
export T2_DECISION_UTC=$(date -u +"%Y-%m-%dT%H:%M:%S.%3NZ")
echo "T2_DECISION_UTC=${T2_DECISION_UTC}"

aws ecs update-service \
  --region "${SECONDARY_REGION}" \
  --cluster "${SECONDARY_ECS_CLUSTER}" \
  --service "${SECONDARY_ECS_SERVICE}" \
  --desired-count 2 \
  --query "service.{Service:serviceName,Desired:desiredCount,Running:runningCount}" \
  --output table
```

### Step 2: Promote Secondary Aurora PostgreSQL Cluster in `ap-south-1`
*Expected Duration: 45 to 110 seconds.*

**Primary Command (Managed Unplanned Global Failover):**
```bash
aws rds failover-global-cluster \
  --region "${SECONDARY_REGION}" \
  --global-cluster-identifier "${GLOBAL_CLUSTER_ID}" \
  --target-db-cluster-identifier "${SECONDARY_CLUSTER_ARN}" \
  --allow-data-loss
```
*(Fallback Command if `us-east-1` global state lock is unreachable: Detach & Promote directly in `ap-south-1`)*:
```bash
# ONLY run if failover-global-cluster is blocked by primary region state lock:
aws rds remove-from-global-cluster \
  --region "${SECONDARY_REGION}" \
  --global-cluster-identifier "${GLOBAL_CLUSTER_ID}" \
  --db-cluster-identifier "${SECONDARY_CLUSTER_ARN}"
```

**Poll Until `ap-south-1` Database Role Flips from `"replica"` to `"writer"`:**
```bash
while true; do
  ROLE=$(curl -s "${SECONDARY_ALB_URL}/health/deep" | jq -r '.db_role')
  echo "$(date -u +"%H:%M:%S") - ap-south-1 db_role: ${ROLE}"
  if [ "${ROLE}" = "writer" ]; then
    export T3_DB_PROMOTED_UTC=$(date -u +"%Y-%m-%dT%H:%M:%S.%3NZ")
    echo "SUCCESS: Aurora ap-south-1 is now WRITER at ${T3_DB_PROMOTED_UTC}"
    break
  fi
  sleep 3
done
```

### Step 3: Flip Route 53 ARC Routing Controls (Make-Before-Break)
*Expected Duration: 5 to 15 seconds.*

> [!CAUTION]
> **ARC Safety Rule Enforcement (`ha-notes-dev-never-both-off-rule`):**  
> Because our Assertion Safety Rule requires `ATLEAST 1` routing control to be `ON` at all times, you **MUST** enable `ap-south-1` (`On`) **BEFORE** disabling `us-east-1` (`Off`). Attempting to turn `us-east-1` `Off` first will be rejected by the ARC data plane with `ValidationException`.

```bash
# 3A. Turn ON Secondary (ap-south-1) Routing Control FIRST -> State: [ON, ON]
aws route53-recovery-cluster update-routing-control-state \
  --routing-control-arn "${ARC_SECONDARY_CONTROL_ARN}" \
  --routing-control-state On \
  --endpoint-url "${ARC_CLUSTER_ENDPOINT}" \
  --region "${ARC_ENDPOINT_REGION}"

# 3B. Turn OFF Primary (us-east-1) Routing Control SECOND -> State: [OFF, ON]
aws route53-recovery-cluster update-routing-control-state \
  --routing-control-arn "${ARC_PRIMARY_CONTROL_ARN}" \
  --routing-control-state Off \
  --endpoint-url "${ARC_CLUSTER_ENDPOINT}" \
  --region "${ARC_ENDPOINT_REGION}"

export T3_ARC_SWITCHED_UTC=$(date -u +"%Y-%m-%dT%H:%M:%S.%3NZ")
echo "T3_ARC_SWITCHED_UTC=${T3_ARC_SWITCHED_UTC}"
```

---

## 4. Verification Gate & RTO / RPO Calculation (`T4`)

1. **Verify Write & Read Capability in `ap-south-1`:**
   ```bash
   curl -i -X POST "${SECONDARY_ALB_URL}/notes" \
     -H "Content-Type: application/json" \
     -d '{"seq_no": 999999, "title": "Post-Failover Verification Write", "content": "Served by promoted ap-south-1 writer"}'

   export T4_RECOVERED_UTC=$(date -u +"%Y-%m-%dT%H:%M:%S.%3NZ")
   echo "T4_RECOVERED_UTC=${T4_RECOVERED_UTC}"
   ```
   - **Expected Output:** `HTTP/1.1 201 Created` with header `X-Served-By-Region: ap-south-1` and body `"written_region": "ap-south-1"`.
2. **Audit RPO (Check Highest Replicated `seq_no`):**
   ```bash
   curl -s "${SECONDARY_ALB_URL}/notes?limit=5" | jq '.stats'
   ```
   - Compare `.stats.max_seq_no` against the final `seq_no` acknowledged by `us-east-1` in `scripts/probe-rpo-rto.js`.

---

## 5. Rollback / Abort Procedure

- **If aborted BEFORE Step 2 (Aurora Promotion):**
  - Ensure `ARC_PRIMARY_CONTROL_ARN` is `On` and `ARC_SECONDARY_CONTROL_ARN` is `Off`.
  - Scale `ap-south-1` ECS back to `desired_count = 1`. Zero data impact.
- **If aborted AFTER Step 2 (Aurora Promotion already executed):**
  - Because `ap-south-1` is now the active database writer, **do not** blindly flip traffic back to `us-east-1` without first syncing storage! Execute **[FAILBACK.md](file:///c:/Users/arif3/OneDrive/Attachments/Desktop/MultiRegioHighAvalabilityUsingAWS/FAILBACK.md)** to perform a clean zero-data-loss (`RPO = 0`) switchover back to `us-east-1`.
