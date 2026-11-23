# Coding Rules & Operational Guardrails (`AGENTS.md`)

**Sources of Truth:** [PRD.md](file:///c:/Users/arif3/OneDrive/Attachments/Desktop/MultiRegioHighAvalabilityUsingAWS/PRD.md), [DESIGN.md](file:///c:/Users/arif3/OneDrive/Attachments/Desktop/MultiRegioHighAvalabilityUsingAWS/DESIGN.md), [ARCHITECTURE.md](file:///c:/Users/arif3/OneDrive/Attachments/Desktop/MultiRegioHighAvalabilityUsingAWS/ARCHITECTURE.md), [DATABASE.md](file:///c:/Users/arif3/OneDrive/Attachments/Desktop/MultiRegioHighAvalabilityUsingAWS/DATABASE.md), [API.md](file:///c:/Users/arif3/OneDrive/Attachments/Desktop/MultiRegioHighAvalabilityUsingAWS/API.md)

Every AI coding agent and human contributor working in this repository MUST strictly enforce the rules in this document.

---

## 1. Terraform Architecture & Style Rules

1. **Zero Hardcoded Regions, Account IDs, or ARNs:**
   - Never hardcode `"us-east-1"` or `"ap-south-1"` inside `modules/*`. Always discover the active region dynamically via `data "aws_region" "current" {}` and the account ID via `data "aws_caller_identity" "current" {}`.
   - Pass `primary_region` and `secondary_region` only from root `variables.tf` / `terraform.tfvars` into the root `provider "aws"` blocks.
2. **Single-Module Multi-Region Reuse:**
   - Never create region-duplicated modules (e.g., `modules/ecs_primary` and `modules/ecs_secondary` are forbidden).
   - Write a single region-agnostic module (`modules/network`, `modules/ecs`, `modules/aurora`, `modules/monitoring`) and instantiate it twice in the root `main.tf` using `providers = { aws = aws.primary }` and `providers = { aws = aws.secondary }`.
   - Exception: Notice that CloudFront ACM certificates must live in `us-east-1`; document this explicitly on the provider passed to `modules/storage_cdn`.
3. **Pinned Versions:**
   - Pin `required_version = ">= 1.6.0, < 2.0.0"` and pin all providers (`hashicorp/aws ~> 5.80`) in `versions.tf`.
4. **Naming & Variable Conventions:**
   - All variables and outputs must use `snake_case` and include `type` and `description`.
   - Resource names in AWS must follow `${var.project_name}-${var.environment}-${local.region_short}-<resource>` (e.g., `ha-notes-dev-use1-alb`, `ha-notes-dev-aps1-alb`).

---

## 2. State Management Rules

1. **Remote Backend & Locking:**
   - Terraform state is stored in an encrypted, versioned S3 bucket provisioned by `bootstrap/` with state locking enabled.
2. **Never Edit State by Hand:**
   - Manual editing of `.tfstate` files is strictly forbidden. Use `terraform state mv`, `terraform import`, or `moved` blocks if refactoring is required.
3. **Never Commit State or Plan Binaries:**
   - `.gitignore` must exclude `*.tfstate*`, `.terraform/`, `*.tfplan`, and `*.tfvars` (except tracked `terraform.tfvars.example` or non-secret `environments/dev/terraform.tfvars`).

---

## 3. Cost Safety & Ephemeral Discipline (CRITICAL)

1. **Mandatory Default Tags on Every Resource:**
   - Configure `default_tags` on both `aws.primary` and `aws.secondary` provider blocks:
     ```hcl
     default_tags {
       tags = {
         Project     = var.project_name
         Environment = var.environment
         ManagedBy   = "Terraform"
         Owner       = var.owner
         CostCenter  = "MultiRegionHA-Lab"
       }
     }
     ```
2. **Feature Flags for High-Cost Resources:**
   - Route 53 ARC Clusters cost **$2.50/hour**. Keep `enable_arc_cluster = false` by default and enable only during Phase 6 and Phase 9 test runs.
   - Keep `enable_aurora_global = false` during Phase 2 & 3 (network/app smoke tests) so database hourly charges only accrue from Phase 4 onward.
3. **Small Instance Sizes Only:**
   - ECS Fargate: `cpu = 256` (0.25 vCPU), `memory = 512` (0.5 GB).
   - Aurora Serverless v2: `min_capacity = 0.5`, `max_capacity = 2.0` ACU.
   - NAT Gateway: `single_nat_gateway = true` (1 per region).
4. **Confirm Before Apply or Destroy:**
   - The agent must **never** execute `terraform apply` or `terraform destroy` against real AWS credentials without showing `terraform plan` output and receiving explicit user confirmation.
5. **Post-Session Teardown Verification:**
   - After every live AWS test session, run `terraform destroy` followed by `scripts/verify-clean-teardown.sh` to verify zero leftover NAT Gateways, Elastic IPs, ALBs, RDS instances, or ARC clusters.

---

## 4. Security Guardrails

1. **No Secrets in Code or Git:**
   - Never hardcode database passwords, Slack webhooks, or AWS keys in `.tf`, `.js`, or `.sh` files.
   - Generate database master passwords with `random_password` and store them directly in `aws_secretsmanager_secret` encrypted with a regional customer-managed KMS key.
2. **Least-Privilege IAM:**
   - Separate `ecs_task_execution_role` (ECR pull + Secrets Manager read for the specific secret ARN + KMS decrypt) from `ecs_task_role` (application runtime permissions).
   - No `Action = "*"` or `Resource = "*"` unless required by a specific AWS service-linked action (must include an inline `# checkov:skip=` comment with written architectural justification).
3. **Encryption Everywhere:**
   - Enable KMS encryption at rest and ` enable_key_rotation = true` on KMS keys, Aurora clusters, S3 buckets, Secrets Manager secrets, ECR repositories, and CloudWatch Log Groups.

---

## 5. Application Code Rules (`app/`)

1. **Container Security:**
   - Multi-stage or slim `node:20-alpine` `Dockerfile`.
   - Run as non-root user (`USER node`).
   - Include a native `HEALTHCHECK` hitting `http://localhost:3000/health`.
2. **Resilience & Observability:**
   - Every response must return `X-Served-By-Region: ${AWS_REGION}`.
   - Structured JSON logging to `stdout` (no sensitive credentials or connection strings logged).
   - Unit and integration tests in `app/test/` runnable via `npm test` without requiring a live AWS connection (using mocks or local pg).

---

## 6. Linting, Static Analysis & Git Discipline

Every change to Terraform or application code must pass the following verification pipeline before being marked complete:

1. `terraform fmt -check -recursive`
2. `terraform validate`
3. `tflint --recursive`
4. `checkov -d . --framework terraform,dockerfile`
5. `npm --prefix app test`

### Attribution & Git Discipline
- Make small, logical commits corresponding to each phase.
- Credit any official AWS samples or open-source Terraform patterns in `README.md`.
- Inspect existing files before modifying them; never perform unrelated rewrites.
