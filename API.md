# Application & Operational API Specification (`API.md`)

**Sources of Truth:** [PRD.md](file:///c:/Users/arif3/OneDrive/Attachments/Desktop/MultiRegioHighAvalabilityUsingAWS/PRD.md), [ARCHITECTURE.md](file:///c:/Users/arif3/OneDrive/Attachments/Desktop/MultiRegioHighAvalabilityUsingAWS/ARCHITECTURE.md), [DATABASE.md](file:///c:/Users/arif3/OneDrive/Attachments/Desktop/MultiRegioHighAvalabilityUsingAWS/DATABASE.md)  
**Runtime:** Node.js 20 LTS (Alpine) + Fastify + `pg` (node-postgres connection pool)  
**Port:** `3000/tcp`

---

## 1. Global Response Headers & Region Identification

To make active region routing and failover transitions immediately visible in `curl`, browser DevTools, and automated RTO/RPO measurement scripts, **every HTTP response** from the application injects the following headers via a Fastify `onSend` hook:

```http
X-Served-By-Region: us-east-1
X-Container-Task-Id: 8f3a1c2d
Cache-Control: no-store
```

---

## 2. REST API Endpoints

### 2.1 `GET /health` (Shallow Liveness Check)
Used by ECS container health checks and basic process liveness probing. Never queries the database so that a database outage does not cause ECS to enter an infinite container-restart loop.

- **Method / Path:** `GET /health`
- **Response (`200 OK`):**
  ```json
  {
    "status": "ok",
    "check_type": "shallow",
    "region": "us-east-1",
    "uptime_seconds": 342.15,
    "timestamp": "2026-11-23T15:30:00.123Z"
  }
  ```

### 2.2 `GET /health/deep` (Deep Readiness & Database Role Check)
Used by the regional **ALB Target Group Health Check** and our **RTO/RPO Failover Probe**. Queries Aurora PostgreSQL (`SELECT pg_is_in_recovery() AS is_replica, NOW() AS db_time;`) with a strict `1,500 ms` query timeout.

- **Why `pg_is_in_recovery()` is a Game-Changer:**
  - In `us-east-1` (Primary Writer), `pg_is_in_recovery()` returns `false` -> `"db_role": "writer"`.
  - In `ap-south-1` (Warm Standby before promotion), `pg_is_in_recovery()` returns `true` -> `"db_role": "replica"`.
  - In `ap-south-1` (Warm Standby), the ALB health check accepts HTTP `200` as long as the database is reachable (even as a replica) so the warm standby task remains registered and ready in the ALB Target Group!
  - As soon as `ap-south-1` Aurora is promoted during failover, `pg_is_in_recovery()` automatically flips to `false` (`"db_role": "writer"`).

- **Response (`200 OK` — Healthy Writer or Healthy Standby Replica):**
  ```json
  {
    "status": "healthy",
    "check_type": "deep",
    "region": "us-east-1",
    "db_reachable": true,
    "db_role": "writer",
    "db_latency_ms": 4,
    "timestamp": "2026-11-23T15:30:00.128Z"
  }
  ```
- **Response (`503 Service Unavailable` — Database Unreachable or Timed Out):**
  ```json
  {
    "status": "unhealthy",
    "check_type": "deep",
    "region": "us-east-1",
    "db_reachable": false,
    "db_role": "unknown",
    "error": "Database connection timeout after 1500ms",
    "timestamp": "2026-11-23T15:30:01.628Z"
  }
  ```

### 2.3 `POST /notes` (Create Note & Record RPO Sequence Number)
Creates a note and records the monotonic sequence number `seq_no` for empirical RPO verification.

- **Request Body (`application/json`):**
  ```json
  {
    "seq_no": 1042,
    "title": "Failover Probe Note #1042",
    "content": "Testing cross-region storage replication to ap-south-1",
    "client_sent_at": "2026-11-23T15:30:02.000Z"
  }
  ```
- **Validation Rules (Fastify JSON Schema):**
  - `seq_no`: required integer `>= 1`.
  - `title`: required non-empty string (`maxLength: 255`).
  - `content`: required string (`maxLength: 4000`).
  - `client_sent_at`: optional ISO-8601 timestamp (defaults to server UTC time if omitted).
- **Response (`201 Created`):**
  ```json
  {
    "id": "c4f1d2e8-7b1a-4c9e-9123-8f9a0b1c2d3e",
    "seq_no": 1042,
    "title": "Failover Probe Note #1042",
    "written_region": "us-east-1",
    "client_sent_at": "2026-11-23T15:30:02.000Z",
    "db_committed_at": "2026-11-23T15:30:02.014Z"
  }
  ```
- **Error Responses:**
  - `400 Bad Request`: Schema validation failed.
  - `409 Conflict`: `seq_no` already exists (`SQLSTATE 23505`).
  - `503 Service Unavailable` (`READ_ONLY_REPLICA`): Returned if a write hits `ap-south-1` *before* Aurora promotion has completed (`SQLSTATE 25006: cannot execute INSERT in a read-only transaction`).
  - `503 Service Unavailable` (`DB_UNAVAILABLE`): Database unreachable.

### 2.4 `GET /notes` (List Recent Notes & RPO Summary Stats)
Returns the most recent notes along with the current `max_seq_no` and `total_count` in the database so a single GET request after failover immediately proves whether any sequence numbers were lost.

- **Query Parameters:** `limit` (optional integer, default `20`, max `100`).
- **Response (`200 OK`):**
  ```json
  {
    "served_by_region": "ap-south-1",
    "db_role": "writer",
    "stats": {
      "total_count": 1042,
      "max_seq_no": 1042,
      "latest_committed_at": "2026-11-23T15:30:02.014Z"
    },
    "notes": [
      {
        "id": "c4f1d2e8-7b1a-4c9e-9123-8f9a0b1c2d3e",
        "seq_no": 1042,
        "title": "Failover Probe Note #1042",
        "content": "Testing cross-region storage replication to ap-south-1",
        "written_region": "us-east-1",
        "client_sent_at": "2026-11-23T15:30:02.000Z",
        "db_committed_at": "2026-11-23T15:30:02.014Z"
      }
    ]
  }
  ```

### 2.5 Standard Error Format
All 4xx/5xx responses return a consistent JSON envelope:
```json
{
  "error": {
    "code": "READ_ONLY_REPLICA",
    "message": "Database is currently a read-only standby replica; promotion in progress.",
    "region": "ap-south-1",
    "timestamp": "2026-11-23T15:31:10.400Z"
  }
}
```

---

## 3. Environment Variables & Injection Method

| Variable | Example Value | Source / Injection Mechanism |
| :--- | :--- | :--- |
| `PORT` | `3000` | ECS Task Definition (`environment`) |
| `AWS_REGION` | `us-east-1` or `ap-south-1` | ECS Task Definition (`environment`, set dynamically from Terraform regional provider) |
| `DB_HOST` | `ha-notes-ap-south-1.cluster-xyz.ap-south-1.rds.amazonaws.com` | ECS Task Definition (`environment`, regional `aws_rds_cluster.this.endpoint`) |
| `DB_PORT` | `5432` | ECS Task Definition (`environment`) |
| `DB_NAME` | `notesdb` | ECS Task Definition (`environment`) |
| `DB_SSL` | `true` | ECS Task Definition (`environment`) |
| `DB_USER` | `notes_admin` | **AWS Secrets Manager** (`secrets` block in Task Definition using JSON key `:username::`) |
| `DB_PASSWORD` | `<32-char-secret>` | **AWS Secrets Manager** (`secrets` block in Task Definition using JSON key `:password::`) |

---

## 4. Database Failure & Promotion Handling in Node.js (`pg` Pool)

A common bug in multi-region warm standby apps occurs when the database is promoted from Read-Only Replica to Writer, but the Node.js `pg.Pool` holds onto stale read-only TCP connections. Our application handles this deterministically:

1. **Aggressive Connection Timeouts:**
   - `connectionTimeoutMillis: 1500`
   - `statement_timeout: 2000`
   - `idleTimeoutMillis: 10000`
2. **Automatic Pool Drain on Read-Only Transaction Error (`SQLSTATE 25006`):**
   - If `POST /notes` catches `error.code === '25006'` (`cannot execute INSERT in a read-only transaction`), the client releases the connection with `client.release(true)` (forcing `pg.Pool` to destroy and open a fresh TCP connection to the newly promoted writer endpoint on the next request) and returns `503 READ_ONLY_REPLICA`.
3. **Auto-Migration on Startup:**
   - On startup, if `pg_is_in_recovery()` is `false` (i.e., running in the primary writer region), the app runs `CREATE TABLE IF NOT EXISTS notes ...` idempotently. If `pg_is_in_recovery()` is `true` (standby replica), it skips DDL migrations and starts serving immediately.

---

## 5. Operational Interfaces (ARC, Region Switch & Step Functions)

### 5.1 Route 53 ARC Routing Control CLI Interface
During failover, routing controls are toggled via the `route53-recovery-cluster` data-plane API against any of the 5 regional cluster endpoints:

```bash
# Step 1: Turn ON Secondary (ap-south-1) FIRST (satisfies Safety Rule: ATLEAST 1 ON)
aws route53-recovery-cluster update-routing-control-state \
  --routing-control-arn "$ARC_CONTROL_ARN_SECONDARY" \
  --routing-control-state On \
  --endpoint-url "$ARC_CLUSTER_ENDPOINT" \
  --region "$ARC_ENDPOINT_REGION"

# Step 2: Turn OFF Primary (us-east-1)
aws route53-recovery-cluster update-routing-control-state \
  --routing-control-arn "$ARC_CONTROL_ARN_PRIMARY" \
  --routing-control-state Off \
  --endpoint-url "$ARC_CLUSTER_ENDPOINT" \
  --region "$ARC_ENDPOINT_REGION"
```

### 5.2 Step Functions Failback Workflow Input Payload
The Step Functions state machine (`ha-notes-failback-orchestrator`) accepts the following JSON input when executing planned failback from `ap-south-1` back to `us-east-1`:

```json
{
  "operation": "PLANNED_FAILBACK",
  "global_cluster_id": "ha-notes-global-db",
  "current_writer_region": "ap-south-1",
  "target_primary_region": "us-east-1",
  "target_primary_cluster_arn": "arn:aws:rds:us-east-1:123456789012:cluster:ha-notes-primary",
  "max_allowed_replication_lag_ms": 2000,
  "arc_control_primary_arn": "arn:aws:route53-recovery-control::123456789012:controlpanel/.../routingcontrol/...",
  "arc_control_secondary_arn": "arn:aws:route53-recovery-control::123456789012:controlpanel/.../routingcontrol/..."
}
```
