# Product Requirements Document (PRD): Multi-Region High Availability & Disaster Recovery on AWS

**Status:** Draft (Pending Architecture & Mentor Review)  
**Architecture Pattern:** Active-Passive Warm Standby  
**Primary Region:** `us-east-1` (N. Virginia) — parameterized  
**Secondary (DR) Region:** `ap-south-1` (Mumbai) — parameterized  
**Sample Application:** Multi-Region Notes & RPO Write-Tracker API (Node.js / Fastify, containerized)

---

## 1. Problem Statement & Project Purpose

### 1.1 The Problem
Single-region cloud deployments are vulnerable to regional impairments—whether caused by control-plane degradation, cascading multi-AZ failures, bad deployments, or data-plane network disruptions. However, many "multi-region" portfolio projects suffer from two critical flaws:
1. **Unverified claims:** They claim "zero downtime" or "sub-second RPO" without empirically measuring replication lag, data loss during unplanned promotion, or actual DNS/routing convergence time.
2. **Dangerous failover mechanisms:** They rely on standard Route 53 DNS health checks (control-plane dependent) rather than independent data-plane routing controls (Route 53 Application Recovery Controller), risking split-brain or stuck failovers during an AWS control-plane incident in `us-east-1`.

### 1.2 What This Project Proves (Portfolio & Learning Goals)
This project designs, provisions, tests, and tears down an **Active-Passive Warm Standby** architecture across `us-east-1` and `ap-south-1`. It proves the ability to:
- Architect **data-plane-first disaster recovery** using **Route 53 Application Recovery Controller (ARC)** routing controls, Region Switch plans, and safety rules.
- Manage stateful cross-region persistence using **Amazon Aurora Global Database (PostgreSQL)**, supporting both planned switchovers (`RPO = 0`) and unplanned detach-and-promote failovers.
- Build **region-agnostic, reusable Terraform modules** invoked across multiple provider aliases (`aws.primary`, `aws.secondary`) with strict cost hygiene.
- Conduct controlled chaos engineering with **AWS Fault Injection Service (FIS)** guarded by CloudWatch stop conditions.
- **Empirically measure RTO and RPO** across multiple trials using a monotonic write-sequence probes and timestamped client telemetry, and execute automated **failback** via **AWS Step Functions**.

---

## 2. Target Audience

1. **Hiring Managers & Staff/Principal Interviewers:** Looking for production maturity—understanding control plane vs. data plane, split-brain prevention, honest limitations of chaos testing, and cost awareness.
2. **Cloud / SRE / Platform Engineers:** Using the repository's `RUNBOOK.md`, `FAILBACK.md`, and Terraform modules as a reproducible reference for warm-standby DR.
3. **The Author (Self):** Mastering multi-region state management, Aurora Global topology lifecycle, ARC clusters, and disciplined operational teardown.

---

## 3. Resilience Goals (Hypotheses to be Measured)

> **Rule:** Target RTO and RPO figures below are **engineering hypotheses**, not guarantees. Final figures will be reported as `[Min, Median, Max]` across at least 3 live failover trials in the final evidence report.

| Metric | Definition in This Project | Target Hypothesis | Measurement Method |
| :--- | :--- | :--- | :--- |
| **RPO (Unplanned Failover)** | Maximum age / count of committed writes in `us-east-1` lost when `ap-south-1` Aurora cluster is forcibly promoted. | **< 2 seconds** (approx. 1–5 writes at 2 writes/sec across US-to-India ~200ms RTT) | Continuous synthetic producer writing sequential `seq_no` + UTC timestamp (`POST /notes`) alongside `AuroraGlobalDBReplicationLag` CloudWatch metric. |
| **RPO (Planned Switchover)** | Committed writes lost during a managed Aurora Global Database switchover. | **0 seconds (Zero data loss)** | Verified by confirming `max(seq_no)` in `ap-south-1` equals the final acknowledged `seq_no` in `us-east-1`. |
| **RTO (Unplanned Failover)** | Elapsed wall-clock time from `T0` (fault injection / primary outage onset) to `T4` (first HTTP 200 write response served by `ap-south-1`). | **< 180 seconds** (1–2 min Aurora promotion + ~15–60s ARC & DNS propagation) | External probe script recording `T0` (fault start), `T1` (alarm fire), `T2` (ARC + Aurora promotion triggered), `T3` (DB writable), `T4` (end-to-end recovery). |

---

## 4. Core Operational Scenarios

1. **Scenario A — Normal Operation:**
   - Primary (`us-east-1`) ARC routing control is `ON`; Secondary (`ap-south-1`) ARC routing control is `OFF`.
   - ECS Fargate in `us-east-1` runs at full capacity (`desired_count = 2`); `ap-south-1` runs warm standby (`desired_count = 1`).
   - Aurora Primary cluster in `us-east-1` handles reads/writes; `ap-south-1` headless/replica cluster receives asynchronous physical storage replication.
   - Responses include header `X-Served-By-Region: us-east-1`.
2. **Scenario B — Regional Failure / Fault Injection:**
   - AWS FIS injects component failures in `us-east-1` (e.g., terminating ECS tasks, blackholing database traffic, or simulating service degradation) with CloudWatch stop alarms monitoring guardrails.
   - Deep health check (`GET /health/deep`) fails in `us-east-1`; CloudWatch alarms notify operators via SNS.
3. **Scenario C — Failover to Secondary (`ap-south-1`):**
   - Operator (or Region Switch execution plan) promotes the `ap-south-1` Aurora cluster to standalone read/write and flips ARC routing controls (`us-east-1` -> `OFF`, `ap-south-1` -> `ON`), respecting the safety rule that both cannot be `OFF` simultaneously.
   - ECS in `ap-south-1` scales up (`desired_count = 2`) and serves read/write traffic (`X-Served-By-Region: ap-south-1`).
4. **Scenario D — Failback to Primary (`us-east-1`):**
   - Once `us-east-1` is healthy, an AWS Step Functions workflow orchestrates re-adding `us-east-1` as a secondary replication target of `ap-south-1`, waits for replication lag to stabilize, performs a planned Aurora switchover back to `us-east-1`, and reverses ARC routing controls.

---

## 5. Functional Requirements per Layer

### 5.1 DNS & Traffic Routing
- **FR-DNS-1:** Route 53 hosted zone (or health-checked failover record set) backed by **Route 53 ARC Routing Controls** across the 5 global ARC cluster endpoints.
- **FR-DNS-2:** An ARC **Assertion Safety Rule** must enforce that at least one region's routing control is `ON` at all times (`both controls never OFF together`).
- **FR-DNS-3:** A **Region Switch Plan** documenting/orchestrating the sequence of scaling ECS, promoting Aurora, and toggling ARC controls.

### 5.2 Frontend & Static Assets
- **FR-FE-1:** S3 bucket in `us-east-1` replicated to an S3 bucket in `ap-south-1` via **S3 Cross-Region Replication (CRR)** (Versioning and KMS/SSE enabled).
- **FR-FE-2:** **Amazon CloudFront** distribution with an Origin Group configured for automatic origin failover (primary origin: `us-east-1`, failover origin: `ap-south-1` on 5xx/timeout) and an ACM certificate provisioned in `us-east-1`.

### 5.3 Compute & Application (Notes API)
- **FR-APP-1:** Containerized Node.js (Fastify) REST API deployed on **ECS Fargate** behind an internet-facing **Application Load Balancer (ALB)** in both regions.
- **FR-APP-2:** Warm standby posture: Primary runs `desired_count = 2` across 2 AZs; Secondary runs `desired_count = 1` continuously so container image, ENI, and DB connection pool are pre-warmed.
- **FR-APP-3:** Application must expose:
  - `POST /notes` & `GET /notes` (CRUD + sequence number tracking for RPO).
  - `GET /health` (shallow liveness for container startup) and `GET /health/deep` (verifies database connectivity and read/write capability).
  - Region metadata (`X-Served-By-Region` header and `"region"` JSON field) on every response.

### 5.4 Database Layer
- **FR-DB-1:** **Amazon Aurora Global Database (PostgreSQL)** with primary writer in `us-east-1` and a secondary read replica instance in `ap-south-1`.
- **FR-DB-2:** KMS encryption at rest enabled in both regions using regional customer-managed KMS keys.

### 5.5 Secrets & Container Registry
- **FR-SEC-1:** Database credentials stored in **AWS Secrets Manager** in `us-east-1` with automated cross-region replication to `ap-south-1`, injected into ECS tasks at runtime.
- **FR-ECR-1:** **Amazon ECR** repository in `us-east-1` configured with cross-region replication rules to automatically push images to `ap-south-1`.

### 5.6 Chaos Engineering & Orchestration
- **FR-FIS-1:** **AWS FIS** experiment templates in `us-east-1` (ECS task termination, network disruption, DB failover) bound to a mandatory CloudWatch Alarm **Stop Condition**.
- **FR-SFN-1:** **AWS Step Functions** state machine to codify and track the multi-step failback sequence.

### 5.7 Provisioning & IaC
- **FR-IAC-1:** 100% provisioned via **Terraform** using reusable modules (`network`, `ecs`, `aurora`, `arc`, `fis`, `monitoring`) with dual provider aliases (`aws.primary`, `aws.secondary`). No hardcoded regions, account IDs, or ARNs.

---

## 6. Non-Functional Requirements (NFRs)

1. **Cost Ceiling & Budget Safety:**
   - **AWS Budgets alarm** deployed in Phase 1 before any compute/database resources (alerting at $10, $25, $50 thresholds).
   - Strict **ephemeral testing discipline**: `terraform destroy` must be executed after every test session to avoid idle hourly charges from Aurora Global DB (~$0.25+/hr), Route 53 ARC Cluster (~$2.50/hr while active!), and NAT Gateways/ALBs.
2. **Security:**
   - Least-privilege IAM roles per service and region (separate ECS Task Execution vs. Task Role, FIS role, Step Functions role).
   - Zero secrets in Git, `.tfvars`, or container images. Static scanning via `checkov` and `tflint`.
3. **Observability:**
   - CloudWatch Dashboards and Alarms deployed in **both** regions (so monitoring survives a `us-east-1` failure).
   - Mandatory alarm on `AuroraGlobalDBReplicationLag` in `ap-south-1`.
4. **Honesty & Scientific Rigor:**
   - Documentation must explicitly state that AWS FIS simulates component/AZ failures within a region, **not** a true AWS regional control/data-plane collapse.
   - Cost multipliers (e.g., 1.3x–1.5x warm standby overhead) must be verified against actual AWS Cost Explorer billing data.

---

## 7. Scope Definition

| Category | Items Included |
| :--- | :--- |
| **MVP Scope** | Dual-region VPCs (`us-east-1`, `ap-south-1`), ECS Fargate + ALB in both regions, Node.js Notes API, Aurora Global PostgreSQL, Secrets Manager & ECR replication, S3 CRR + CloudFront, Route 53 ARC routing controls + safety rule, CloudWatch alarms (`AuroraGlobalDBReplicationLag`), FIS experiment with stop condition, Step Functions failback workflow, measured RTO/RPO, `RUNBOOK.md`, `FAILBACK.md`, `COST.md`. |
| **Stretch Goals** | Automated Region Switch execution trigger, CloudWatch Synthetics canary, Slack webhook integration via SNS, AWS WAF on CloudFront. |
| **Out of Scope** | Active-Active multi-master writes (conflict resolution), multi-cloud failover (e.g., AWS to GCP), Kubernetes (EKS), zero-downtime schema migration frameworks for breaking DDL changes. |

---

## 8. Success Criteria & Deliverables Checklist

- [ ] Architecture diagram clearly distinguishes **Normal Path (solid arrows)** vs. **Failover Path (dashed arrows)**.
- [ ] `terraform validate`, `tflint`, and `checkov` pass in CI.
- [ ] Both `us-east-1` and `ap-south-1` stacks deploy cleanly from the same reusable Terraform modules.
- [ ] Unplanned failover and planned failback executed at least **3 times**, producing raw timestamped logs and a `[Min, Median, Max]` RTO/RPO table.
- [ ] FIS experiment executed and verified that its CloudWatch Stop Condition halts the experiment when breached.
- [ ] `RUNBOOK.md`, `FAILBACK.md`, and `COST.md` (with real AWS Cost Explorer screenshots/figures) completed.
- [ ] 2-to-3 minute walkthrough demo video recorded and linked in `README.md`.
- [ ] Full stack cleanly destroyed (`terraform destroy`) with post-session check confirming $0/hr residual run rate.

---

## 9. Assumptions & Decisions Needing Approval

### Labeled Assumptions
1. **A1 (Cross-Region Latency):** Because primary is `us-east-1` (N. Virginia) and secondary is `ap-south-1` (Mumbai), physical network round-trip time (RTT) is ~180–220 ms. We assume `AuroraGlobalDBReplicationLag` under light write load will rest around **200 ms – 800 ms** (higher than same-continent pairs like `us-east-1` to `us-west-2`), which is an awesome talking point for interviews!
2. **A2 (Aurora Engine):** We assume **Aurora PostgreSQL Serverless v2** (scaled down to `0.5 ACU` min) or `db.r6g.large` depending on Global Database support and lowest hourly cost for short test windows.

### Approved Architectural Decisions
1. **D1 — Domain & TLS Strategy (Approved):** No mandatory custom domain purchase. We use the default CloudFront domain (`*.cloudfront.net`) with default TLS (`cloudfront_default_certificate = true`) for zero-cost static/edge routing, while parameterizing `custom_domain_name` (optional) so an ACM certificate in `us-east-1` and Route 53 public records activate automatically if provided. Route 53 ARC routing controls and health checks are verified via a private/test hosted zone and direct ARC data-plane cluster endpoints.
2. **D2 — Networking Cost Strategy (Approved):** **1 NAT Gateway per region** (`single_nat_gateway = true`). ECS Fargate tasks and Aurora PostgreSQL remain in private subnets (production security posture) while capping NAT hourly cost to ~$0.09/hr across both regions during ephemeral test sessions.
3. **D3 — Route 53 ARC Cluster Cost Guardrail (Approved):** The Route 53 ARC Cluster ($2.50/hr) is gated behind `enable_arc_cluster = false` by default and enabled only during Phase 6 and Phase 9 failover verification sessions.
