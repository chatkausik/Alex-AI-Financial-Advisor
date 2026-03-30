# Alex — Agentic Learning Equities eXplainer

### Multi-Agent Enterprise-Grade SaaS Financial Planning Platform

![Alex Platform](assets/alex.png)

> **Alex** is a production-ready AI system that analyzes equity portfolios through intelligent multi-agent collaboration — delivering personalized reports, visualizations, and retirement projections powered by AWS Bedrock and the OpenAI Agents SDK.

**Live:** `https://d19rsg3zmbspay.cloudfront.net`

---

## What Alex Does

Alex is a SaaS platform where users connect their equity portfolios and receive AI-driven insights:

- **Portfolio Analysis** — Deep analysis of holdings, sector exposure, and risk profile
- **Market Research** — Autonomous web research on each instrument using Playwright
- **Retirement Projections** — Monte Carlo simulations and long-term forecasting
- **Interactive Charts** — AI-generated visualizations of portfolio performance
- **Real-time Prices** — Live market data via Polygon.io

---

## Architecture

```
User Browser
     │
     ▼
CloudFront CDN (d19rsg3zmbspay.cloudfront.net)
     │
     ├──► S3 Bucket ──► NextJS Static Frontend (Clerk Auth)
     │
     └──► API Gateway ──► FastAPI Lambda (JWT validation)
                               │
                               ▼
                          Aurora Serverless v2
                          SQS Queue (jobs)
                               │
                               ▼
                     Planner Agent (Orchestrator)
                    /          |          |        \
                   ▼           ▼          ▼         ▼
                Tagger     Reporter    Charter  Retirement
                   \           |          |        /
                    └──────────▼──────────▼───────┘
                              Aurora DB
                        (report + chart + retirement payloads)
                               │
                               ▼
                     Frontend polls → displays results
```

### Core Services

| Layer | Technology |
|-------|-----------|
| LLM | AWS Bedrock — Nova Pro (`us.amazon.nova-pro-v1:0`) |
| Agents | OpenAI Agents SDK + LiteLLM |
| Compute | AWS Lambda (5 agents + API) |
| Database | Aurora Serverless v2 PostgreSQL (Data API) |
| Vector Store | S3 Vectors + SageMaker embeddings |
| Orchestration | SQS + Lambda event source mapping |
| Research | App Runner + Playwright MCP |
| Frontend | NextJS + Clerk Auth + CloudFront |
| Observability | LangFuse |
| IaC | Terraform |

---

## Repository Structure

```
alex/
├── guides/              # Step-by-step deployment guides (START HERE)
│   ├── 1_permissions.md
│   ├── 2_sagemaker.md
│   ├── 3_ingest.md
│   ├── 4_researcher.md
│   ├── 5_database.md
│   ├── 6_agents.md
│   ├── 7_frontend.md
│   └── 8_enterprise.md
│
├── backend/             # All agent code
│   ├── planner/         # Orchestrator — routes tasks to sub-agents
│   ├── tagger/          # Classifies instruments (sector, asset class, etc.)
│   ├── reporter/        # Writes portfolio analysis reports
│   ├── charter/         # Generates charts and visualizations
│   ├── retirement/      # Retirement projections and Monte Carlo
│   ├── researcher/      # Autonomous market research (App Runner)
│   ├── ingest/          # Document ingestion Lambda
│   ├── database/        # Shared database library
│   └── api/             # FastAPI backend for frontend
│
├── frontend/            # NextJS React application
│
├── terraform/           # Per-guide Terraform (independent local state)
│   ├── 2_sagemaker/
│   ├── 3_ingestion/
│   ├── 4_researcher/
│   ├── 5_database/
│   ├── 6_agents/
│   ├── 7_frontend/
│   └── 8_enterprise/
│
├── infra/               # Unified Terraform (CI/CD, all guides together)
│   ├── bootstrap/       # One-time: S3 state bucket + DynamoDB locks
│   ├── modules/         # sagemaker, ingestion, database, agents, frontend
│   ├── environments/    # dev.tfvars, test.tfvars, prod.tfvars
│   └── main.tf
│
└── .github/workflows/
    ├── deploy.yml       # CI/CD deploy to dev / test / prod
    └── destroy.yml      # CI/CD destroy with confirmation gate
```

---

## Deployment Guide

### Prerequisites

- AWS account with IAM user `aiengineer` configured (`aws configure`)
- Docker Desktop installed and running
- [uv](https://docs.astral.sh/uv/) installed (`curl -LsSf https://astral.sh/uv/install.sh | sh`)
- Node.js 20+
- Terraform 1.7+
- [Clerk](https://clerk.com) account (free tier works)
- [LangFuse](https://cloud.langfuse.com) account (free tier works)
- [Polygon.io](https://polygon.io) API key (free tier works)

---

### Guide 1 — AWS Permissions

Set up IAM permissions so your `aiengineer` user can deploy everything Alex needs.

```bash
# Follow guides/1_permissions.md
# Creates AlexAccess IAM group with all required policies
```

---

### Guide 2 — SageMaker Embeddings

Deploy a serverless SageMaker endpoint running `all-MiniLM-L6-v2` for vector embeddings.

```bash
cd terraform/2_sagemaker
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your values
terraform init && terraform apply
```

> Takes ~5 minutes. Note the `endpoint_name` output — you'll need it in later guides.

---

### Guide 3 — Ingestion Pipeline

Create the S3 Vectors bucket and Lambda ingestion function (90% cheaper than OpenSearch).

```bash
cd terraform/3_ingestion
cp terraform.tfvars.example terraform.tfvars
terraform init && terraform apply
```

Test ingestion:
```bash
cd backend/ingest
uv run test_ingest.py
```

---

### Guide 4 — Researcher Agent

Deploy an autonomous research agent on App Runner with Playwright web browsing.

```bash
cd backend/researcher
uv run package_docker.py          # Build Docker image (Docker must be running)

cd terraform/4_researcher
cp terraform.tfvars.example terraform.tfvars
terraform init && terraform apply
```

> Uses AWS Bedrock Nova Pro (`us.amazon.nova-pro-v1:0`). Make sure you have model access enabled in the Bedrock console.

---

### Guide 5 — Aurora Database

Deploy Aurora Serverless v2 PostgreSQL with Data API enabled (no VPC complexity).

```bash
cd terraform/5_database
cp terraform.tfvars.example terraform.tfvars
terraform init && terraform apply
```

Once the cluster reaches `available` status (~10 minutes), run migrations and seed data:

```bash
cd backend/database

# Update .env with the ARNs from terraform output
# AURORA_CLUSTER_ARN=<from terraform output aurora_cluster_arn>
# AURORA_SECRET_ARN=<from terraform output aurora_secret_arn>

uv run run_migrations.py          # Creates all tables
uv run seed_data.py               # Loads 22 ETF instruments
```

> **Important:** The `.env` file uses `load_dotenv(override=True)`. Always ensure your `.env` has the correct ARNs for the environment you're targeting — incorrect ARNs cause migrations to silently run against the wrong cluster.

---

### Guide 6 — AI Agent Orchestra

Deploy all 5 Lambda agents with SQS orchestration — the heart of Alex.

```bash
# Build all agent packages (Docker must be running)
cd backend
uv run package_docker.py

cd terraform/6_agents
cp terraform.tfvars.example terraform.tfvars
terraform init && terraform apply
```

Test locally (no AWS required):
```bash
cd backend
MOCK_LAMBDAS=true uv run test_simple.py
```

Test on AWS:
```bash
cd backend
uv run test_full.py
```

> **Bedrock model access:** Go to the AWS Bedrock console → Model access → Enable Nova Pro (`us.amazon.nova-pro-v1:0`). If using inference profiles for cross-region access, enable model access in each region the profile covers.

---

### Guide 7 — Frontend & API

Deploy the NextJS frontend with Clerk auth, CloudFront CDN, and FastAPI Lambda backend.

```bash
# 1. Create a Clerk application at clerk.com
# 2. Configure frontend environment
cp frontend/.env.local.example frontend/.env.local
# Fill in NEXT_PUBLIC_CLERK_PUBLISHABLE_KEY

# 3. Deploy infrastructure
cd terraform/7_frontend
cp terraform.tfvars.example terraform.tfvars
# Fill in clerk_jwks_url, clerk_issuer from your Clerk dashboard
terraform init && terraform apply

# 4. Build and deploy frontend
cd scripts
uv run deploy.py
```

Once deployed, your app will be live at the `cloudfront_url` output from Terraform.

---

### Guide 8 — Enterprise Grade

Add observability (LangFuse), CloudWatch dashboards, and monitoring.

```bash
cd terraform/8_enterprise
cp terraform.tfvars.example terraform.tfvars
terraform init && terraform apply
```

LangFuse tracing is automatically enabled in all agents when `LANGFUSE_PUBLIC_KEY` and `LANGFUSE_SECRET_KEY` are set.

---

## CI/CD with GitHub Actions

The unified `infra/` Terraform supports one-click deploy and destroy across environments.

### How it works

1. **Package job** — Builds all 7 Lambda zip files using Docker (agents) and uv (api, ingest)
2. **Deploy job** — Downloads artifacts, bootstraps S3 state bucket idempotently, runs `terraform plan` + `terraform apply`, then builds and deploys the NextJS frontend to S3/CloudFront

### One-Time Bootstrap

The first time you run the CI/CD pipeline it will automatically create the remote state infrastructure:

- S3 bucket: `alex-terraform-state-<account-id>` (versioned, encrypted)
- DynamoDB table: `alex-terraform-locks`
- IAM group: `AlexCICD` with inline policy covering all required services

### GitHub Secrets Required

Add these in **Settings → Secrets → Actions**:

| Secret | Where to get it |
|--------|----------------|
| `AWS_ACCESS_KEY_ID` | IAM → Users → aiengineer → Security credentials |
| `AWS_SECRET_ACCESS_KEY` | Same as above |
| `OPENAI_API_KEY` | platform.openai.com |
| `POLYGON_API_KEY` | polygon.io |
| `CLERK_JWKS_URL` | `https://<instance>.clerk.accounts.dev/.well-known/jwks.json` |
| `CLERK_ISSUER` | `https://<instance>.clerk.accounts.dev` |
| `LANGFUSE_PUBLIC_KEY` | cloud.langfuse.com → Settings → API Keys |
| `LANGFUSE_SECRET_KEY` | Same as above |
| `NEXT_PUBLIC_CLERK_PUBLISHABLE_KEY` | Clerk dashboard → API Keys |

### GitHub Environments

Create three environments in **Settings → Environments**:

| Environment | Protection Rules |
|-------------|-----------------|
| `dev` | None — auto deploys |
| `test` | None — auto deploys |
| `prod` | Required reviewers + wait timer |

### Deploy

Go to **Actions → Deploy Alex → Run workflow** → select environment → Run

### Destroy

Go to **Actions → Destroy Alex → Run workflow** → select environment → type the environment name to confirm

---

## Environment Comparison

| Setting | dev | test | prod |
|---------|-----|------|------|
| Aurora max ACU | 1 | 2 | 8 |
| Planner memory | 1024 MB | 2048 MB | 3072 MB |
| Agent memory | 512 MB | 1024 MB | 1024 MB |
| Monitoring | No | Yes | Yes |
| Custom domain | No | No | Yes |
| Est. monthly cost | ~$45 | ~$55 | ~$70 |

> Aurora Serverless v2 is the biggest cost driver (~$43/mo at min ACU). Run `terraform destroy` when not actively developing.

---

## Cost Management

```bash
# Destroy via CI/CD (recommended)
# Actions → Destroy Alex → select environment → confirm

# Or destroy locally in reverse order:
cd terraform/8_enterprise && terraform destroy
cd terraform/7_frontend   && terraform destroy
cd terraform/6_agents     && terraform destroy
cd terraform/5_database   && terraform destroy   # Biggest savings
cd terraform/4_researcher && terraform destroy
cd terraform/3_ingestion  && terraform destroy
cd terraform/2_sagemaker  && terraform destroy
```

---

## Key Configuration Files

| File | Purpose |
|------|---------|
| `.env` | Root environment variables — update as you complete each guide |
| `frontend/.env.local` | Frontend Clerk keys and API URL |
| `terraform/*/terraform.tfvars` | Per-guide Terraform config (copy from `.example`) |
| `infra/environments/*.tfvars` | Unified Terraform per-environment config |

---

## Troubleshooting

### "Failed to sync user: 500" on dashboard

The Aurora database schema hasn't been applied. Run:

```bash
cd backend/database
uv run run_migrations.py
uv run seed_data.py
```

Make sure `.env` has the correct `AURORA_CLUSTER_ARN` and `AURORA_SECRET_ARN` for your deployed cluster (not a stale value from a previous deployment). The script uses `load_dotenv(override=True)` so the `.env` file takes priority over inline env vars.

---

### Analysis completes but shows no data (empty Overview/Charts/Retirement tabs)

The Planner agent can't invoke sub-agents because function names don't include the environment prefix.

**Cause:** The planner defaults to `alex-reporter`, but deployed functions are named `alex-dev-reporter`, `alex-test-reporter`, etc.

**Fix:** Ensure the following environment variables are set on the Planner Lambda:

| Variable | Value |
|----------|-------|
| `REPORTER_FUNCTION` | `alex-<env>-reporter` |
| `CHARTER_FUNCTION` | `alex-<env>-charter` |
| `RETIREMENT_FUNCTION` | `alex-<env>-retirement` |
| `TAGGER_FUNCTION` | `alex-<env>-tagger` |

These are automatically set when deploying through the unified `infra/` Terraform or the CI/CD pipeline. If deploying manually per-guide, add them to your `terraform.tfvars`.

---

### Docker packaging fails with PermissionError

Docker installs Lambda dependencies as root. Python's `TemporaryDirectory` cleanup fails with `EPERM` on root-owned files.

**Fix:** All `package_docker.py` scripts use `TemporaryDirectory(delete=False)` to skip cleanup entirely. The CI runner workspace is ephemeral so this is safe.

If you see a `Mounts Denied` error locally, add `/tmp` (or the directory mentioned in the error) to Docker Desktop's shared paths: **Settings → Resources → File Sharing**.

---

### Terraform plan fails: "one of filename,image_uri,s3_bucket must be specified"

Lambda zip files don't exist on disk at plan time (e.g., you haven't run `package_docker.py` yet).

**Fix:** All Lambda functions in the `infra/` unified Terraform use S3-based deployment. Build the packages first:

```bash
# Agent Lambdas (requires Docker)
cd backend && uv run package_docker.py

# API Lambda (requires Docker)
cd backend/api && uv run package_docker.py

# Ingest Lambda (no Docker needed)
cd backend/ingest && uv sync && uv run package.py
```

Then run `terraform plan` again.

---

### Bedrock: "Access denied" or "Model not found"

1. Go to AWS Bedrock console → **Model access**
2. Request access to **Nova Pro** (`us.amazon.nova-pro-v1:0`)
3. If using cross-region inference profiles, enable model access in every region the profile covers (typically `us-east-1`, `us-west-2`, `eu-west-1`)
4. Verify `BEDROCK_REGION` in your `.env` / `terraform.tfvars` matches where you have access

> Note: LiteLLM requires `AWS_REGION_NAME` (not `AWS_REGION` or `DEFAULT_AWS_REGION`) for Bedrock. This is set automatically by the Terraform modules.

---

### Aurora: "relation does not exist"

The schema migrations haven't run against the correct cluster. Verify the cluster ARN in `.env`:

```bash
# Get the correct ARN
aws rds describe-db-clusters \
  --query 'DBClusters[?contains(DBClusterIdentifier,`alex`)].{ID:DBClusterIdentifier,ARN:DBClusterArn}' \
  --output table

# Then update .env and re-run
cd backend/database
uv run run_migrations.py
```

---

## Built By

**Kausik** — [GitHub](https://github.com/chatkausik/Alex-AI-Financial-Advisor)

Built as a capstone project for the *AI in Production* course, deploying a complete enterprise-grade multi-agent AI system to AWS from scratch.
