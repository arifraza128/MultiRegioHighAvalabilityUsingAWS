# Phased Implementation Plan (`PLAN.md`)

**Sources of Truth:** [PRD.md](file:///c:/Users/arif3/OneDrive/Attachments/Desktop/MultiRegioHighAvalabilityUsingAWS/PRD.md), [DESIGN.md](file:///c:/Users/arif3/OneDrive/Attachments/Desktop/MultiRegioHighAvalabilityUsingAWS/DESIGN.md), [ARCHITECTURE.md](file:///c:/Users/arif3/OneDrive/Attachments/Desktop/MultiRegioHighAvalabilityUsingAWS/ARCHITECTURE.md), [DATABASE.md](file:///c:/Users/arif3/OneDrive/Attachments/Desktop/MultiRegioHighAvalabilityUsingAWS/DATABASE.md), [API.md](file:///c:/Users/arif3/OneDrive/Attachments/Desktop/MultiRegioHighAvalabilityUsingAWS/API.md), [AGENTS.md](file:///c:/Users/arif3/OneDrive/Attachments/Desktop/MultiRegioHighAvalabilityUsingAWS/AGENTS.md)

This 10-phase delivery plan follows a strict **Foundations First, Ephemeral Cost Discipline** model. Every phase is independently verifiable, has an explicit hourly cost exposure calculation, and can be cleanly destroyed before moving on.

---

## Phase Overview & Cost Exposure Matrix

| Phase | Phase Name | Modules Affected | Est. Hourly Cost (While Running) | Feature Flags Active |
| :---: | :--- | :--- | :---: | :--- |
| **1** | Repo Foundation, Remote State & Budget Alarm | `bootstrap/`, root `.tf` skeleton | **$0.00 / hr** (Free tier S3 + Budget) | All flags `false` |
| **2** | Primary Network & Sample App (`us-east-1`) | `app/`, `modules/network`, `modules/ecs` | **~$0.09 / hr** (1 NAT GW + 1 ALB + 2 Fargate 0.25 vCPU) | `enable_secondary_region = false` |
| **3** | Secondary Region Warm Standby (`ap-south-1`) | `modules/network`, `modules/ecs` (2nd provider) | **~$0.17 / hr** (2 NAT GWs + 2 ALBs + 3 Fargate tasks) | `enable_secondary_region = true` |
| **4** | Aurora Global DB + Secrets & ECR Replication | `modules/aurora`, `modules/ecs` | **~$0.30 / hr** (+2 Aurora Serverless v2 0.5 ACU + 2 Secrets + 2 KMS) | `enable_aurora_global = true` |
| **5** | S3 Cross-Region Replication + CloudFront + ACM | `modules/storage_cdn` | **~$0.30 / hr** (S3 + CloudFront usage-based pennies) | `enable_storage_cdn = true` |
| **6** | Route 53 ARC Routing Controls & Safety Rules | `modules/arc` | **~$2.80 / hr** (+$2.50/hr Route 53 ARC Cluster!) | `enable_arc_cluster = true` |
| **7** | Multi-Region Monitoring, Dashboards & Alarms | `modules/monitoring` | **~$0.31 / hr** (with ARC off) | `enable_monitoring = true` |
| **8** | AWS FIS Chaos Experiments & Stop Conditions | `modules/fis` | **~$0.31 / hr** ($0.10/experiment-minute only during run) | `enable_fis = true` |
| **9** | Live Failover, Step Functions Failback & RTO/RPO | `modules/failback`, `scripts/` | **~$2.80 / hr** (1-to-2 hour timed test window = **~$5 total**) | All flags `true` |
| **10** | Final Teardown, Cost Report, Runbooks & Demo Video | `COST.md`, `RUNBOOK.md`, `FAILBACK.md`, `README.md` | **$0.00 / hr** (Post-destroy verified) | Stack destroyed |

---

## Detailed Phase Breakdown

### Phase 1: Repository Setup, State Backend & Budget Alarm
- **Goal:** Establish the repository structure, Git hooks, CI lint/security pipeline, encrypted S3 remote state backend with locking, and an AWS Budgets alarm ($10 / $25 / $50 thresholds).
- **Tasks:**
  1. Create `bootstrap/` Terraform configuration for the S3 state bucket, KMS encryption, and `aws_budgets_budget` cost alarm.
  2. Create root Terraform structure (`versions.tf`, `providers.tf`, `variables.tf`, `main.tf`, `outputs.tf`, `environments/dev/terraform.tfvars`).
  3. Configure `.gitignore`, `.tflint.hcl`, `.pre-commit-config.yaml`, `.github/workflows/ci.yml`, `Makefile`, and `scripts/verify-clean-teardown.sh`.
- **Modules Affected:** `bootstrap/`, root skeleton.
- **Prerequisites:** AWS CLI configured with credentials, Terraform >= 1.6 installed.
- **Estimated Cost Exposure:** **$0.00/hr** (< $0.05/month for S3 state files; first 2 AWS Budgets are free).
- **Tests & Completion Criteria:** `terraform fmt -check -recursive`, `terraform validate` pass on both `bootstrap/` and root.
- **Evidence to Capture:** Screenshot/log of active AWS Budget alarm and `terraform validate` output.

---

### Phase 2: Primary Region Network + Sample App (`us-east-1`)
- **Goal:** Containerize the Node.js (Fastify) Notes API and deploy it into `us-east-1` (`modules/network` + `modules/ecs`) with 1 NAT Gateway, Public ALB, and 2 Fargate tasks.
- **Tasks:**
  1. Build `app/` (Fastify API with `/health`, `/health/deep`, `POST /notes`, `GET /notes`, `X-Served-By-Region` header) + unit tests + `Dockerfile`.
  2. Implement `modules/network` (VPC `10.10.0.0/16`, 2 Public, 2 Private App, 2 Isolated DB subnets, 1 NAT GW, Flow Logs).
  3. Implement `modules/ecs` (ECR repository, ALB, Target Group, ECS Cluster, Fargate Service `desired_count = 2`, least-privilege Task/Execution IAM roles).
- **Modules Affected:** `app/`, `modules/network`, `modules/ecs`.
- **Prerequisites:** Phase 1 complete; Docker installed locally (or CI build).
- **Estimated Cost Exposure:** **~$0.09/hr** (1 NAT GW $0.045/hr + 1 ALB $0.0225/hr + 2 Fargate tasks $0.024/hr).
- **Tests & Completion Criteria:**
  - `npm --prefix app test` passes locally.
  - `curl -i http://<us-east-1-alb>/health` returns `200 OK` and `X-Served-By-Region: us-east-1`.
- **Evidence to Capture:** `curl -i` output from `us-east-1` ALB and passing unit test log.

---

### Phase 3: Secondary Region Warm Standby (`ap-south-1`)
- **Goal:** Prove 100% module reusability by instantiating the exact same `modules/network` and `modules/ecs` in `ap-south-1` via `providers = { aws = aws.secondary }` with `desired_count = 1` and ECR cross-region replication.
- **Tasks:**
  1. Enable ECR Cross-Region Replication rule in `us-east-1` targeting `ap-south-1`.
  2. Instantiate `module "network_secondary"` (`10.20.0.0/16`) and `module "ecs_secondary"` (`desired_count = 1`) in root `main.tf`.
- **Modules Affected:** `modules/network`, `modules/ecs`, root `main.tf`.
- **Prerequisites:** Phase 2 complete.
- **Estimated Cost Exposure:** **~$0.17/hr** across both regions.
- **Tests & Completion Criteria:**
  - Push image to `us-east-1` ECR and verify automatic appearance in `ap-south-1` ECR.
  - `curl -i http://<ap-south-1-alb>/health` returns `200 OK` and `X-Served-By-Region: ap-south-1`.
- **Evidence to Capture:** ECR replication screenshot/CLI output and dual-region `curl` headers.

---

### Phase 4: Aurora Global Database + Secrets Manager Replication
- **Goal:** Deploy encrypted Aurora Global PostgreSQL (`db.serverless`, `0.5–2.0 ACU`) across `us-east-1` (Writer) and `ap-south-1` (Read Replica), replicate database credentials via Secrets Manager, and connect the Notes API.
- **Tasks:**
  1. Implement `modules/aurora` (KMS keys in both regions, Secrets Manager primary + replica, `aws_rds_global_cluster`, primary cluster/instance, secondary cluster/instance).
  2. Wire `DB_HOST` and Secrets Manager ARNs into `modules/ecs` in both regions.
  3. Test write in `us-east-1` (`POST /notes` with `seq_no: 1`) and verify read in `ap-south-1` (`GET /notes`) + check `/health/deep` (`"db_role": "writer"` in `us-east-1`, `"db_role": "replica"` in `ap-south-1`).
- **Modules Affected:** `modules/aurora`, `modules/ecs`, root `main.tf`.
- **Prerequisites:** Phase 3 complete.
- **Estimated Cost Exposure:** **~$0.30/hr** (+~$0.12/hr for two 0.5 ACU Serverless v2 instances + KMS/Secrets).
- **Tests & Completion Criteria:**
  - Note written to `us-east-1` appears in `ap-south-1` `GET /notes` within < 1 second.
  - Direct `POST /notes` to `ap-south-1` ALB returns `503 READ_ONLY_REPLICA` (proving standby safety).
- **Evidence to Capture:** CLI log showing cross-region data replication and `/health/deep` outputs from both regions.

---

### Phase 5: S3 Cross-Region Replication + CloudFront Origin Group
- **Goal:** Deploy static frontend/status assets with automatic edge failover using S3 CRR (`us-east-1` -> `ap-south-1`) and a CloudFront distribution configured with an Origin Group.
- **Tasks:**
  1. Implement `modules/storage_cdn` (Primary S3 bucket, Replica S3 bucket, KMS encryption, Versioning, CRR IAM role & rule, CloudFront Origin Access Control, Origin Group failing over on `500/502/503/504`, optional ACM cert in `us-east-1`).
  2. Upload `index.html` status dashboard and verify replication to `ap-south-1`.
- **Modules Affected:** `modules/storage_cdn`.
- **Prerequisites:** Phase 1 complete (independent of DB).
- **Estimated Cost Exposure:** **<$0.01/hr** incremental.
- **Tests & Completion Criteria:** Upload object to `us-east-1` S3 bucket, verify `ReplicationStatus = COMPLETED` in `ap-south-1`, and fetch via CloudFront domain.
- **Evidence to Capture:** `aws s3api head-object` output showing `ReplicationStatus: "COMPLETED"` and CloudFront response headers.

---

### Phase 6: Route 53 ARC Routing Controls & Safety Rules
- **Goal:** Provision the Route 53 Application Recovery Controller (ARC) Cluster, Control Panel, two Routing Controls (`us-east-1`, `ap-south-1`), Assertion Safety Rule (`ATLEAST 1 ON`), and Route 53 Health Checks + Failover DNS records.
- **Tasks:**
  1. Implement `modules/arc` gated behind `var.enable_arc_cluster`.
  2. Configure `aws_route53recoverycontrolconfig_safety_rule` enforcing that both routing controls cannot be `OFF` simultaneously.
  3. Test setting both controls to `OFF` via the data-plane CLI and verify that ARC rejects the request (`ValidationException: Safety rule violated`).
- **Modules Affected:** `modules/arc`.
- **Prerequisites:** Phase 3 complete.
- **Estimated Cost Exposure:** **+$2.50/hr** while `enable_arc_cluster = true`. Turn off or proceed immediately into Phase 9 and destroy after testing!
- **Tests & Completion Criteria:** Safety rule rejection test passes; routing control toggle succeeds in Make-Before-Break order (`[ON, OFF] -> [ON, ON] -> [OFF, ON]`).
- **Evidence to Capture:** Terminal log showing the ARC Safety Rule blocking an invalid `OFF` command.

---

### Phase 7: Multi-Region Monitoring, Dashboards & Alerting
- **Goal:** Deploy CloudWatch Dashboards, Alarms (including `AuroraGlobalDBReplicationLag`), and SNS Topics in **both** `us-east-1` and `ap-south-1`.
- **Tasks:**
  1. Implement `modules/monitoring` (deployed in both `aws.primary` and `aws.secondary`).
  2. Provision regional alarms: `ALB-5xx-High`, `ALB-Unhealthy-Hosts`, `ECS-Running-Tasks-Low`, and `Aurora-Global-Replication-Lag-High` (`> 5000 ms` in `ap-south-1`).
  3. Provision SNS topics in both regions (with email/webhook subscription support).
- **Modules Affected:** `modules/monitoring`.
- **Prerequisites:** Phases 3 & 4 complete.
- **Estimated Cost Exposure:** **~$0.01/hr** incremental.
- **Tests & Completion Criteria:** CloudWatch Dashboards render live metrics in both regions; `aws cloudwatch set-alarm-state` test triggers SNS notification.
- **Evidence to Capture:** Screenshots of `us-east-1` and `ap-south-1` CloudWatch Dashboards including `AuroraGlobalDBReplicationLag`.

---

### Phase 8: AWS FIS Chaos Experiments & CloudWatch Stop Conditions
- **Goal:** Build controlled chaos engineering experiments in `us-east-1` using AWS Fault Injection Service (FIS) bound to mandatory CloudWatch Stop Conditions.
- **Tasks:**
  1. Implement `modules/fis` with least-privilege IAM role and three experiment templates:
     - `fis-ecs-task-termination`: Stops 100% of ECS tasks in `us-east-1`.
     - `fis-network-blackhole`: Disrupts subnet connectivity to simulate AZ/regional data-plane degradation.
     - `fis-aurora-failover`: Triggers DB instance reboot/failover.
  2. Bind every template to the `FIS-Stop-Condition-Alarm` so experiments halt automatically if guardrail thresholds breach.
- **Modules Affected:** `modules/fis`.
- **Prerequisites:** Phase 7 complete.
- **Estimated Cost Exposure:** **$0.10 per experiment-minute** only while an experiment is actively running.
- **Tests & Completion Criteria:** Trigger FIS experiment with a pre-tripped Stop Condition alarm and verify FIS aborts within seconds (`State: stopped`).
- **Evidence to Capture:** AWS FIS execution log showing stop-condition enforcement and task termination events.

---

### Phase 9: Failover, Step Functions Failback & Empirical RTO/RPO Measurement
- **Goal:** Execute 3 full end-to-end disaster recovery trials (Baseline -> FIS Fault Injection -> ARC + Aurora Failover to `ap-south-1` -> Step Functions Failback to `us-east-1`) and record raw `[Min, Median, Max]` RTO and RPO data.
- **Tasks:**
  1. Implement `modules/failback` (AWS Step Functions state machine orchestrating replica verification, `switchover-global-cluster`, and ARC control reset).
  2. Build `scripts/probe-rpo-rto.js` (writes sequential `seq_no` at 2 req/s, logs `T0, T1, T2, T3, T4` timestamps, and computes exact RTO in seconds and RPO in lost sequence numbers).
  3. Execute 3 trials following `RUNBOOK.md` and `FAILBACK.md`, saving JSON logs to `evidence/`.
  4. Immediately run `terraform destroy` and `scripts/verify-clean-teardown.sh`.
- **Modules Affected:** `modules/failback`, `scripts/`, `evidence/`.
- **Prerequisites:** Phases 1–8 complete.
- **Estimated Cost Exposure:** **~$2.80/hr** for ~1.5 hours = **~$4.20 total session cost**.
- **Tests & Completion Criteria:** 3 completed trials with raw JSON evidence logs and clean post-session teardown (`0` remaining resources).
- **Evidence to Capture:** `evidence/trial-1.json`, `trial-2.json`, `trial-3.json`, Step Functions execution graph screenshot, teardown audit output.

---

### Phase 10: Final Documentation, Cost Report & Demo Video
- **Goal:** Package all empirical evidence into `RUNBOOK.md`, `FAILBACK.md`, `COST.md`, `README.md`, and a 2–3 minute demo video script, then run the Final Production Audit (Prompt 20).
- **Tasks:**
  1. Finalize `RUNBOOK.md` and `FAILBACK.md` with exact timings observed in Phase 9.
  2. Author `COST.md` comparing estimated monthly warm-standby cost vs. actual AWS Cost Explorer charges from our test sessions.
  3. Author `README.md` and `DEMO_SCRIPT.md` with full credits and interview talking points.
- **Estimated Cost Exposure:** **$0.00/hr** (all AWS resources already destroyed).
- **Completion Criteria:** Verdict `READY` on Prompt 20 Final Production Audit.

---

## Recommended First Task
Begin **Phase 1 (Prompt 8 — Project Setup)** right now: initialize the repository folder structure, `bootstrap/` state backend + budget alarm, root Terraform dual-region providers (`aws.primary` and `aws.secondary`), linting/security configuration, and validate with `terraform fmt` and `terraform validate`.
