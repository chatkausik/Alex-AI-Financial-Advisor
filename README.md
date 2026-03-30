# Alex — Agentic Learning Equities eXplainer

### Multi-Agent Enterprise-Grade SaaS Financial Planning Platform

![Alex Platform](assets/alex.png)

> **Alex** is a production-ready AI system that analyzes equity portfolios through intelligent multi-agent collaboration — delivering personalized reports, visualizations, and retirement projections powered by AWS Bedrock and the OpenAI Agents SDK.

---

## What Alex Does

Alex is a SaaS platform where users connect their equity portfolios and receive AI-driven insights:

- **Portfolio Analysis** — Deep analysis of holdings, sector exposure, and risk profile
- **Market Research** — Autonomous web research on each instrument using Playwright
- **Retirement Projections** — Monte Carlo simulations and long-term forecasting
- **Interactive Charts** — AI-generated visualizations of portfolio performance
- **Real-time Data** — Live market prices via Polygon.io

---

## Architecture

```
User Request
     │
     ▼
API Gateway ──► FastAPI Lambda (Auth via Clerk JWT)
                     │
                     ▼
               SQS Queue
                     │
                     ▼
            Planner Agent (Orchestrator)
           /         |          |        \
          ▼          ▼          ▼         ▼
       Tagger    Reporter    Charter  Retirement
          \          |          |        /
           \         ▼          ▼       /
            └──────► Results → Aurora DB
                                │
                                ▼
                     CloudFront + NextJS Frontend
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
├── terraform/           # Per-guide Terraform (independent state)
│   ├── 2_sagemaker/
│   ├── 3_ingestion/
│   ├── 4_researcher/
│   ├── 5_database/
│   ├── 6_agents/
│   ├── 7_frontend/
│   └── 8_enterprise/
│
├── infra/               # Unified Terraform (all guides, CI/CD ready)
│   ├── bootstrap/       # One-time: S3 state bucket + DynamoDB locks
│   ├── modules/         # sagemaker, ingestion, database, agents, frontend, monitoring
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
- [Clerk](https://clerk.com) account
- [LangFuse](https://cloud.langfuse.com) account
- [Polygon.io](https://polygon.io) API key

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
uv run package_docker.py          # Build Docker image

cd terraform/4_researcher
cp terraform.tfvars.example terraform.tfvars
terraform init && terraform apply
```

---

### Guide 5 — Aurora Database

Deploy Aurora Serverless v2 PostgreSQL with Data API (no VPC complexity).

```bash
cd terraform/5_database
cp terraform.tfvars.example terraform.tfvars
terraform init && terraform apply

# Wait ~10 mins for cluster to reach "available", then:
cd backend/database
uv run migrate.py                 # Create schema
uv run seed.py                    # Load 22 ETFs seed data
```

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

Test locally:
```bash
cd backend
uv run test_simple.py             # Local mock test
```

Test on AWS:
```bash
PYTHONPATH=/path/to/alex/backend/database uv run test_full.py
```

---

### Guide 7 — Frontend & API

Deploy the NextJS frontend with Clerk auth, CloudFront CDN, and FastAPI Lambda backend.

```bash
# 1. Set up Clerk — create account at clerk.com, get your keys
# 2. Configure frontend environment
cp frontend/.env.local.example frontend/.env.local
# Fill in your Clerk keys and API URL

# 3. Deploy infrastructure
cd terraform/7_frontend
cp terraform.tfvars.example terraform.tfvars
terraform init && terraform apply

# 4. Build and deploy frontend
cd scripts
uv run deploy.py
```

---

### Guide 8 — Enterprise Grade

Add observability (LangFuse), CloudWatch dashboards, and explainability features.

```bash
cd terraform/8_enterprise
cp terraform.tfvars.example terraform.tfvars
terraform init && terraform apply
```

LangFuse tracing is automatically enabled in all agents when `LANGFUSE_PUBLIC_KEY` and `LANGFUSE_SECRET_KEY` are set in your environment.

---

## CI/CD with GitHub Actions

The unified `infra/` Terraform supports one-click deploy and destroy across environments.

### One-Time Bootstrap

```bash
cd infra/bootstrap
terraform init && terraform apply
# Creates S3 state bucket + DynamoDB locks + AlexCICD IAM group
```

### GitHub Secrets Required

Add these in **Settings → Secrets → Actions**:

| Secret | Description |
|--------|-------------|
| `AWS_ACCESS_KEY_ID` | IAM user access key |
| `AWS_SECRET_ACCESS_KEY` | IAM user secret key |
| `OPENAI_API_KEY` | OpenAI key |
| `POLYGON_API_KEY` | Polygon.io market data key |
| `CLERK_JWKS_URL` | `https://<your-instance>.clerk.accounts.dev/.well-known/jwks.json` |
| `CLERK_ISSUER` | `https://<your-instance>.clerk.accounts.dev` |
| `LANGFUSE_PUBLIC_KEY` | LangFuse `pk-lf-...` |
| `LANGFUSE_SECRET_KEY` | LangFuse `sk-lf-...` |
| `NEXT_PUBLIC_CLERK_PUBLISHABLE_KEY` | Clerk publishable key |

### GitHub Environments

Create three environments in **Settings → Environments**:

| Environment | Protection |
|-------------|-----------|
| `dev` | None (auto-deploy) |
| `test` | None (auto-deploy) |
| `prod` | Required reviewers + wait timer |

### Deploy

Go to **Actions → Deploy Alex → Run workflow** → select environment → Run

### Destroy

Go to **Actions → Destroy Alex → Run workflow** → select environment → type environment name to confirm

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

> Aurora is the biggest cost driver (~$43/mo). Run `terraform destroy` when not actively developing.

---

## Cost Management

```bash
# Destroy in reverse order to minimize costs
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

## Built By

**Kausik** — [GitHub](https://github.com/chatkausik/Alex-AI-Financial-Advisor)

Built as part of the *AI in Production* course, deploying a complete enterprise-grade multi-agent AI system to AWS.
