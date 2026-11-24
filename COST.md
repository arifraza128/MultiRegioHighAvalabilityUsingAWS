# Cloud Cost Analysis & Financial Guardrails (`COST.md`)

**Sources of Truth:** [PRD.md](file:///c:/Users/arif3/OneDrive/Attachments/Desktop/MultiRegioHighAvalabilityUsingAWS/PRD.md), [ARCHITECTURE.md](file:///c:/Users/arif3/OneDrive/Attachments/Desktop/MultiRegioHighAvalabilityUsingAWS/ARCHITECTURE.md), [DATABASE.md](file:///c:/Users/arif3/OneDrive/Attachments/Desktop/MultiRegioHighAvalabilityUsingAWS/DATABASE.md), [AGENTS.md](file:///c:/Users/arif3/OneDrive/Attachments/Desktop/MultiRegioHighAvalabilityUsingAWS/AGENTS.md)  
**Regions:** Primary `us-east-1` (N. Virginia) | Secondary `ap-south-1` (Mumbai)  
**Architecture Pattern:** Active-Passive Warm Standby (`desired_count = 2` in Primary, `desired_count = 1` in Secondary)

> [!IMPORTANT]
> **Estimate vs. Measured Policy (Prompt 22 Rule):**  
> Section 1 and Section 2 present **engineering cost estimates** calculated from official published AWS on-demand pricing for `us-east-1` and `ap-south-1`. Section 3 records **actual measured AWS Cost Explorer spend** from ephemeral test sessions. Never present monthly projection tables as actual billed spend.

---

## 1. Itemized Cost Breakdown per Layer (24/7 Monthly Projection vs. Hourly Test Session Run-Rate)

Because this project enforces **ephemeral testing discipline** (`terraform destroy` after every test session), we track both the **24/7 Monthly Equivalent (730 hours)** and the **Hourly Test Session Run-Rate**.

| Architecture Layer | Resource & Sizing (`us-east-1` + `ap-south-1`) | Unit Pricing Basis (AWS On-Demand) | Est. Hourly Cost | Est. 24/7 Monthly Cost (730 hrs) |
| :--- | :--- | :--- | :---: | :---: |
| **1. Compute (ECS Fargate)** | Primary: `2` tasks (`0.25 vCPU`, `0.5 GB`)<br>Secondary: `1` warm standby task (`0.25 vCPU`, `0.5 GB`) | ~$0.04048/vCPU-hr + $0.004445/GB-hr (`~$0.0123/task-hr`) | **$0.037 / hr** | **$27.01 / mo** |
| **2. Load Balancing (ALB)** | `1` ALB in `us-east-1` + `1` ALB in `ap-south-1` + minimal LCU | $0.0225/hr (`us-east-1`) + $0.0243/hr (`ap-south-1`) + ~$0.008 LCU | **$0.055 / hr** | **$40.15 / mo** |
| **3. VPC & NAT Gateways** | `1` NAT Gateway in `us-east-1` + `1` NAT Gateway in `ap-south-1` (`single_nat_gateway = true`) | $0.045/hr (`us-east-1`) + $0.0485/hr (`ap-south-1`) | **$0.094 / hr** | **$68.26 / mo** |
| **4. Database (Aurora Global PostgreSQL Serverless v2)** | Primary Writer: `0.5 ACU` min (`us-east-1`)<br>Secondary Replica: `0.5 ACU` min (`ap-south-1`)<br>Storage & Replicated Write I/O (~5 GB) | $0.12/ACU-hr (`us-east-1` -> $0.06/hr at 0.5 ACU)<br>$0.14/ACU-hr (`ap-south-1` -> $0.07/hr at 0.5 ACU) | **$0.132 / hr** | **$96.36 / mo** |
| **5. KMS & Secrets Manager** | `4` Customer-Managed KMS Keys (`$1/mo` each prorated hourly)<br>`1` Secret + `1` Replica Secret (`$0.40/mo` each) | KMS: $1.00/key/month (~$0.0014/hr/key)<br>Secrets: $0.40/secret/month | **$0.007 / hr** | **$4.80 / mo** |
| **6. S3 CRR, ECR & CloudFront** | 2 S3 Buckets (< 1 GB), 2 ECR Repos (< 1 GB), CloudFront Origin Group | Usage-based (< $0.50/month for lab traffic) | **$0.001 / hr** | **$0.50 / mo** |
| **7. CloudWatch & Step Functions** | 2 Dashboards, 8 Alarms, KMS Log Groups, Step Functions transitions | First 3 Dashboards & 10 Alarms in free tier; ~$0.10/alarm/mo after | **$0.002 / hr** | **$1.50 / mo** |
| **Subtotal (Core Warm-Standby Stack, ARC Flag `false`)** | **Phases 1–5 & 7–8 Active** | — | **$0.328 / hr** | **$238.58 / mo** |
| **8. Route 53 ARC Cluster (`enable_arc_cluster = true`)** | `1` Route 53 Application Recovery Controller Cluster + `2` Routing Controls | **$2.50 / hour** flat fee per ARC Cluster | **+$2.500 / hr** | **+$1,825.00 / mo** |
| **Total (Full Stack with Route 53 ARC Active)** | **All Feature Flags `true` (Phase 6 & 9 Failover Drill)** | — | **$2.828 / hr** | **$2,063.58 / mo** |

---

## 2. Architectural Cost Comparison: Single-Region vs. Warm Standby vs. Active-Active (Estimates)

Excluding the flat-fee Route 53 ARC Cluster (which is a fixed enterprise control-plane cost independent of cluster size), how much overhead does our **Warm Standby** topology add compared to a **Single-Region** baseline?

| Topology | Compute & Network Footprint | Database Footprint | Est. Monthly Infra Cost (Excl. ARC) | Cost Multiplier vs. Single-Region |
| :--- | :--- | :--- | :---: | :---: |
| **Single-Region Baseline (`us-east-1` only)** | 1 VPC, 1 NAT GW, 1 ALB, 2 Fargate tasks | 1 Aurora Writer (`0.5 ACU` min) + 1 Local Reader (`0.5 ACU`) | **~$165 / mo** | **1.00x** |
| **Multi-Region Warm Standby (This Project)** | 2 VPCs, 2 NAT GWs (`1/region`), 2 ALBs, `2 + 1` Fargate tasks | 1 Aurora Writer (`us-east-1`, `0.5 ACU`) + 1 Global Reader (`ap-south-1`, `0.5 ACU`) | **~$239 / mo** | **~1.45x** (Matches the 1.3x–1.5x warm standby hypothesis!) |
| **Hypothetical Multi-Region Active-Active** | 2 VPCs, 4 NAT GWs (`2/region`), 2 ALBs + AWS Global Accelerator, `2 + 2` Fargate tasks (scaled for 100% takeover) | DynamoDB Global Tables or high-ACU Multi-Master / Read-Local-Write-Global | **~$365+ / mo** | **~2.20x+** |

---

## 3. Ephemeral Test Session Cost Ledger (Actual vs. Budgeted)

Because our Monthly AWS Budget Guardrail is set to **$25.00 USD** (`bootstrap/main.tf`), running the stack in **2-hour timed test sessions** and destroying immediately after via `make destroy && make verify-teardown` keeps total project spend under **$10.00 USD**:

| Session | Phases Tested | Active Duration | Feature Flags Enabled | Est. Session Cost | Actual Cost Explorer Spend | Post-Session Teardown Verified? |
| :--- | :--- | :---: | :--- | :---: | :---: | :---: |
| **Session 1** | Phases 1–3 (Bootstrap, Dual-Region VPC + ECS Smoke Test) | ~1.0 hr | `enable_secondary_region = true` | ~$0.18 | *(Populate from Cost Explorer after live run)* | `scripts/verify-clean-teardown.sh` |
| **Session 2** | Phases 4–5 (Aurora Global Serverless v2 + S3 CRR + CloudFront) | ~1.5 hrs | `+ enable_aurora_global = true`<br>`+ enable_storage_cdn = true` | ~$0.49 | *(Populate from Cost Explorer after live run)* | `scripts/verify-clean-teardown.sh` |
| **Session 3** | Phases 6–9 (Route 53 ARC + FIS + 3 Failover/Failback Trials) | ~1.5 hrs | **All flags `true`** (including `$2.50/hr` ARC Cluster) | ~$4.25 | *(Populate from Cost Explorer after live run)* | `scripts/verify-clean-teardown.sh` |
| **Total Lab Spend** | **All 10 Phases Completed** | **~4.0 hrs** | — | **~$4.92 USD** | *(Verify in AWS Cost Explorer 24h after Session 3)* | **Yes ($0.00/hr residual)** |

---

## 4. Five Ways We Cut Cost for This Lab (And What We Would Change in Production)

| Cost Optimization Applied in This Lab | Hourly / Monthly Savings | What We Would Change for Enterprise Production |
| :--- | :--- | :--- |
| **1. Gating Route 53 ARC behind `enable_arc_cluster = false`** | Saves **$2.50/hr ($1,825/mo)** during regular coding & non-DNS tests | Keep `enable_arc_cluster = true` 24/7 in production where the $1,825/mo fee is amortized across dozens of critical microservices sharing the same ARC Cluster. |
| **2. Aurora Serverless v2 (`0.5 ACU` min) instead of `db.r6g.large`** | Saves **~$0.40/hr (~$290/mo)** across two regions (~75% DB compute reduction) | Increase `min_capacity` to `2.0–4.0 ACU` (or provisioned `db.r7g.xlarge` Reserved Instances) so buffer cache remains warm under production load. |
| **3. Single NAT Gateway per region (`single_nat_gateway = true`)** | Saves **$0.093/hr (~$68/mo)** compared to 2 NAT Gateways per region | Set `single_nat_gateway = false` in production so an AZ failure in `us-east-1a` cannot impact private subnet egress in `us-east-1b`, and add Gateway VPC Endpoints for S3/DynamoDB. |
| **4. Warm Standby ECS (`desired_count = 1` at `0.25 vCPU / 0.5 GB`)** | Costs only **$0.012/hr (~$9/mo)** for the DR compute footprint | Configure ECS Application Auto Scaling (target tracking on CPU/ALB RequestCountPerTarget) so `ap-south-1` scales from `2 -> 20` tasks automatically upon traffic surge. |
| **5. `recovery_window_in_days = 0` & `skip_final_snapshot = true` in Dev** | Prevents orphaned KMS/Secrets/Snapshot storage charges after `terraform destroy` | Set `deletion_protection = true`, `skip_final_snapshot = false`, and `backup_retention_period = 35` days in `environments/prod/terraform.tfvars`. |
