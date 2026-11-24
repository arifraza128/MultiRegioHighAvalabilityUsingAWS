# 2-to-3 Minute Portfolio Demo Video Script (`DEMO_SCRIPT.md`)

**Target Duration:** 2 minutes 45 seconds  
**Screen Layout Recommendation:**
- **Left Half of Screen:** Terminal split vertically:
  - *Top-Left:* `node scripts/probe-rpo-rto.js` printing live `POST /notes` writes (`seq_no`, `X-Served-By-Region`, latency).
  - *Bottom-Left:* Operator terminal for triggering AWS FIS, Aurora Promotion, and Route 53 ARC commands.
- **Right Half of Screen:** Browser with 3 tabs open:
  1. GitHub `README.md` Architecture Diagram (Solid Normal Path vs. Dashed Failover Path).
  2. CloudWatch Dashboard (`ha-notes-dev-aps1-ha-dashboard` showing `AuroraGlobalDBReplicationLag`).
  3. AWS Step Functions Console (`ha-notes-dev-aps1-failback-orchestrator`).

---

## Scene 1: Problem & Architecture Overview (0:00 – 0:35)

**[Visual]:** Show the Architecture Diagram in `README.md` on the right and the live `probe-rpo-rto.js` terminal on the left writing `seq_no=1, 2, 3...` to `us-east-1`.

**[Voiceover]:**
> "Most multi-region portfolio demos make two mistakes: they rely on standard Route 53 control-plane health checks—which are hosted in `us-east-1` and can stall during a `us-east-1` control-plane outage—and they claim 'sub-second RPO' without measuring actual lost writes.
>
> In this project, I built an Active-Passive Warm Standby architecture across **N. Virginia (`us-east-1`)** and **Mumbai (`ap-south-1`)** using reusable Terraform modules.
>
> On the left, my synthetic probe is writing sequential notes (`seq_no: 10, 11, 12...`) to our containerized Fastify API on ECS Fargate in `us-east-1`. Every response returns `X-Served-By-Region: us-east-1`. Under the hood, Aurora Global PostgreSQL Serverless v2 replicates storage blocks asynchronously to `ap-south-1` with around 250 milliseconds of cross-continental replication lag."

---

## Scene 2: Chaos Fault Injection with CloudWatch Stop Conditions (0:35 – 1:10)

**[Visual]:** In the bottom-left terminal, start the AWS FIS experiment (`aws fis start-experiment`). Watch the top-left probe immediately log `[T0 FAULT DETECTED]`.

**[Voiceover]:**
> "Let's inject a failure in `us-east-1` using **AWS Fault Injection Service (FIS)**. Every FIS template in our repository is bound to a mandatory CloudWatch Stop Condition alarm so chaos experiments abort automatically if safety guardrails breach—and as noted in our docs, we're transparent that FIS simulates component failures, not a full AWS regional blackout.
>
> As soon as the primary tasks terminate, our probe records timestamp **T0** and logs the last acknowledged sequence number in `us-east-1`."

---

## Scene 3: Data-Plane Failover via Aurora Promotion & Route 53 ARC (1:10 – 2:05)

**[Visual]:** Run the failover script (`RUNBOOK.md`): promote `ap-south-1` Aurora cluster, watch `/health/deep` flip from `"db_role": "replica"` to `"writer"`, and toggle Route 53 ARC Routing Controls.

**[Voiceover]:**
> "Now we execute our failover runbook against `ap-south-1`. Notice our warm standby ECS task in Mumbai is already running and pre-warmed (`desired_count = 1`), reporting `db_role: replica` on `/health/deep`.
>
> First, we promote the `ap-south-1` Aurora cluster and scale ECS to 2 tasks. When Postgres finishes promotion, `/health/deep` automatically flips from `replica` to `writer`—and our Node.js connection pool evicts stale read-only sockets on `SQLSTATE 25006` without needing a container restart.
>
> Next, we shift traffic using **Route 53 Application Recovery Controller (ARC)** data-plane endpoints. Because our ARC **Assertion Safety Rule** enforces that at least one region is always `ON`, it rejects any attempt to turn both regions off. We follow a Make-Before-Break sequence: turning `ap-south-1` `ON` first, then `us-east-1` `OFF`."

---

## Scene 4: Empirical RTO / RPO Results & Automated Step Functions Failback (2:05 – 2:45)

**[Visual]:** Point to the probe terminal printing `[T4 RECOVERY CONFIRMED]` with `X-Served-By-Region: ap-south-1` and the JSON summary block, then show the green Step Functions execution graph in Tab 3.

**[Voiceover]:**
> "At timestamp **T4**, our probe automatically recovers with `X-Served-By-Region: ap-south-1` and outputs the empirical JSON report: exact **RTO in seconds (`T4 - T0`)** and exact **RPO in lost sequence numbers** by comparing the highest acknowledged `seq_no` in `us-east-1` against `MAX(seq_no)` in `ap-south-1`.
>
> Finally, once `us-east-1` is healthy, we trigger our **AWS Step Functions Failback Orchestrator** hosted in `ap-south-1`. It verifies replication sync and executes a managed Aurora Global Database switchover, returning primary writer duties to `us-east-1` with **zero data loss (`RPO = 0`)**, before we run `make destroy` and our teardown audit script to bring our hourly AWS cost back to zero."
