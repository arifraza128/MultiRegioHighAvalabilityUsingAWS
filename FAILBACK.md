# Disaster Recovery Failback Runbook: Planned Return to Primary (`FAILBACK.md`)

**Sources of Truth:** [DESIGN.md](file:///c:/Users/arif3/OneDrive/Attachments/Desktop/MultiRegioHighAvalabilityUsingAWS/DESIGN.md), [DATABASE.md](file:///c:/Users/arif3/OneDrive/Attachments/Desktop/MultiRegioHighAvalabilityUsingAWS/DATABASE.md), [API.md](file:///c:/Users/arif3/OneDrive/Attachments/Desktop/MultiRegioHighAvalabilityUsingAWS/API.md)  
**Scenario:** Planned Return from Active DR (`ap-south-1`) back to Recovered Primary (`us-east-1`)  
**Target RPO:** **`0 seconds` (Zero Data Loss)** via Managed Aurora Global Database Switchover  
**Orchestrator:** AWS Step Functions (`ha-notes-dev-aps1-failback-orchestrator` in `ap-south-1`)

---

## 1. Failback Architecture & Why RPO = 0

Unlike an unplanned outage where the primary dies unexpectedly, **Failback is a planned maintenance operation**.
1. While `ap-south-1` has been serving as the promoted Writer, new notes (`seq_no`) were committed in `ap-south-1`.
2. Before shifting traffic back to `us-east-1`, we verify that `us-east-1` is attached to the Global Cluster as a healthy Secondary Replica receiving physical storage replication from `ap-south-1`.
3. We invoke the **AWS Step Functions Failback State Machine** in `ap-south-1`, which executes `rds:SwitchoverGlobalCluster`. AWS briefly pauses incoming writes, drains 100% of remaining replication log records to `us-east-1` (`RPO = 0`), promotes `us-east-1` back to Primary Writer, and demotes `ap-south-1` back to Secondary Replica.

---

## 2. Preconditions Checklist

1. **Verify Any Active AWS FIS Chaos Experiments Are Stopped:**
   ```bash
   aws fis list-experiments --region us-east-1 \
     --query "experiments[?state.status=='running'].{ID:id,State:state.status}" --output table
   ```
2. **Verify `us-east-1` ECS Tasks Are Healthy (`desired_count = 2`):**
   ```bash
   curl -s "${PRIMARY_ALB_URL}/health/deep" | jq .
   ```
   - **Expected Output:** `HTTP 200` with `"status": "healthy"`, `"db_reachable": true`, `"db_role": "replica"` (since `ap-south-1` is currently the writer and `us-east-1` is the replica).
3. **Verify Replication Lag from `ap-south-1` -> `us-east-1` is `< 2,000 ms`:**
   ```bash
   bash scripts/measure-replication-lag.sh "us-east-1" "ha-notes-dev-use1-aurora-cluster" 10
   ```

---

## 3. Step-by-Step Failback Execution

### Step 1: Trigger the AWS Step Functions Failback State Machine (`ap-south-1`)
*Expected Duration: 60 to 120 seconds.*

```bash
export FAILBACK_START_UTC=$(date -u +"%Y-%m-%dT%H:%M:%S.%3NZ")
export SFN_ARN=$(terraform output -raw failback_state_machine_arn)
export GLOBAL_CLUSTER_ID=$(terraform output -raw aurora_global_cluster_id)
export PRIMARY_CLUSTER_ARN="arn:aws:rds:us-east-1:$(terraform output -raw account_id):cluster:ha-notes-dev-use1-aurora-cluster"

EXECUTION_ARN=$(aws stepfunctions start-execution \
  --region ap-south-1 \
  --state-machine-arn "${SFN_ARN}" \
  --name "failback-$(date -u +%Y%m%d-%H%M%S)" \
  --input "{
    \"operation\": \"PLANNED_FAILBACK\",
    \"global_cluster_id\": \"${GLOBAL_CLUSTER_ID}\",
    \"current_writer_region\": \"ap-south-1\",
    \"target_primary_region\": \"us-east-1\",
    \"target_primary_cluster_arn\": \"${PRIMARY_CLUSTER_ARN}\"
  }" \
  --query "executionArn" --output text)

echo "Started Step Functions Execution: ${EXECUTION_ARN}"
```

### Step 2: Poll Step Functions Execution Until `SUCCEEDED`
```bash
while true; do
  STATUS=$(aws stepfunctions describe-execution \
    --region ap-south-1 \
    --execution-arn "${EXECUTION_ARN}" \
    --query "status" --output text)
  echo "$(date -u +"%H:%M:%S") - Step Functions Failback Status: ${STATUS}"
  if [ "${STATUS}" = "SUCCEEDED" ]; then
    break
  elif [ "${STATUS}" = "FAILED" ] || [ "${STATUS}" = "TIMED_OUT" ] || [ "${STATUS}" = "ABORTED" ]; then
    echo "ERROR: Step Functions execution ended with ${STATUS}"
    exit 1
  fi
  sleep 5
done
```

> **Note if Manual Detach (`remove-from-global-cluster`) Was Used During Failover:**  
> If `ap-south-1` was detached from the Global Cluster rather than switched over via `failover-global-cluster`, re-attach `us-east-1` as a replica of `ap-south-1` first (`aws rds create-global-cluster` / `modify-db-cluster`), wait for sync, and then run Step 1 above.

### Step 3: Confirm `us-east-1` Resumed `"db_role": "writer"`
```bash
curl -s "${PRIMARY_ALB_URL}/health/deep" | jq .
```
- **Expected Output:** `"db_role": "writer"` in `us-east-1`, and `"db_role": "replica"` in `ap-south-1`.

### Step 4: Reverse Route 53 ARC Routing Controls (Make-Before-Break)
*Expected Duration: 5 to 15 seconds.*

```bash
# 4A. Turn ON Primary (us-east-1) FIRST -> State: [ON, ON]
aws route53-recovery-cluster update-routing-control-state \
  --routing-control-arn "${ARC_PRIMARY_CONTROL_ARN}" \
  --routing-control-state On \
  --endpoint-url "${ARC_CLUSTER_ENDPOINT}" \
  --region "${ARC_ENDPOINT_REGION}"

# 4B. Turn OFF Secondary (ap-south-1) SECOND -> State: [ON, OFF]
aws route53-recovery-cluster update-routing-control-state \
  --routing-control-arn "${ARC_SECONDARY_CONTROL_ARN}" \
  --routing-control-state Off \
  --endpoint-url "${ARC_CLUSTER_ENDPOINT}" \
  --region "${ARC_ENDPOINT_REGION}"
```

### Step 5: Scale Down Secondary (`ap-south-1`) ECS Service Back to Warm Standby (`2 -> 1`)
```bash
aws ecs update-service \
  --region ap-south-1 \
  --cluster "${SECONDARY_ECS_CLUSTER}" \
  --service "${SECONDARY_ECS_SERVICE}" \
  --desired-count 1 \
  --query "service.{Service:serviceName,Desired:desiredCount}" \
  --output table

export FAILBACK_END_UTC=$(date -u +"%Y-%m-%dT%H:%M:%S.%3NZ")
echo "FAILBACK COMPLETE AT ${FAILBACK_END_UTC}"
```

---

## 4. Post-Failback Verification (`RPO = 0` Audit)

```bash
curl -s "${PRIMARY_ALB_URL}/notes?limit=5" | jq '{region: .served_by_region, db_role: .db_role, stats: .stats}'
```
- Confirm that `.served_by_region == "us-east-1"`, `.db_role == "writer"`, and `.stats.max_seq_no` includes every single note written in `ap-south-1` during the failover window (`Zero Data Loss`).
