# Alex — AI Financial Advisor

### Enterprise-Grade Multi-Agent Portfolio Analysis Platform

![Alex Platform](assets/alex.png)

> **Alex** is a production SaaS application I built that analyzes equity portfolios through a coordinated system of AI agents — delivering personalized reports, interactive charts, and retirement projections powered by AWS Bedrock, the OpenAI Agents SDK, and a fully serverless AWS infrastructure.

**Production:** [kausik-digital-twin.com](https://kausik-digital-twin.com) &nbsp;|&nbsp; **Dev:** [d19rsg3zmbspay.cloudfront.net](https://d19rsg3zmbspay.cloudfront.net)

---

## What It Does

Users sign in with Clerk, connect their equity portfolios, and trigger an AI analysis. Five specialized agents collaborate in parallel to produce:

- **Portfolio Overview** — Holdings breakdown, sector exposure, risk profile, and personalized recommendations
- **Interactive Charts** — AI-generated visualizations of allocation, performance, and diversification
- **Retirement Projection** — Monte Carlo simulations and long-term wealth forecasting based on user goals
- **Market Research** — Autonomous web research on each instrument using Playwright MCP
- **Real-time Prices** — Live market data via Polygon.io with automatic instrument tagging

---

## Architecture

```
User Browser
     │
     ▼
CloudFront CDN  ──►  S3  ──►  NextJS Frontend (Clerk Auth)
     │
     └──►  API Gateway  ──►  FastAPI Lambda  ──►  Aurora DB + SQS
                                                        │
                                              ┌─────────▼──────────┐
                                              │   Planner Agent     │
                                              │   (Orchestrator)    │
                                              └──┬──────┬──────┬───┘
                                                 │      │      │
                                        ┌────────▼─┐ ┌──▼───┐ ▼──────────────┐
                                        │ Reporter │ │Charter│  Retirement    │
                                        │  Agent   │ │ Agent │    Agent       │
                                        └────────┬─┘ └──┬───┘ └──────┬───────┘
                                                 │      │             │
                                              ┌──▼──────▼─────────────▼──┐
                                              │      Aurora Serverless    │
                                              │  (report + charts +       │
                                              │   retirement payloads)    │
                                              └───────────────────────────┘
```

### Agent Roles

| Agent | Role |
|-------|------|
| **Planner** | Orchestrator — receives job from SQS, fetches live prices, invokes sub-agents in parallel |
| **Tagger** | Classifies instruments by sector, asset class, and geographic region |
| **Reporter** | Writes the portfolio analysis report with actionable insights |
| **Charter** | Generates chart data (allocation pies, performance lines, sector breakdown) |
| **Retirement** | Projects retirement outcomes using Monte Carlo simulation |

### Technology Stack

| Layer | Technology |
|-------|-----------|
| LLM | AWS Bedrock — Nova Pro (`us.amazon.nova-pro-v1:0`) |
| Agent Framework | OpenAI Agents SDK + LiteLLM (Bedrock adapter) |
| Compute | AWS Lambda (Python 3.12, Docker-packaged) |
| Database | Aurora Serverless v2 PostgreSQL with Data API |
| Vector Store | AWS S3 Vectors + SageMaker `all-MiniLM-L6-v2` embeddings |
| Orchestration | Amazon SQS + Lambda event source mapping |
| Research | AWS App Runner + Playwright MCP server |
| Auth | Clerk (JWT validation in FastAPI Lambda) |
| Frontend | NextJS (static export) + CloudFront + S3 |
| IaC | Terraform — both per-guide and unified CI/CD |
| Observability | LangFuse distributed tracing |
| CI/CD | GitHub Actions — build, package, deploy, destroy |

---

## Infrastructure Design

The platform runs entirely serverless on AWS with no always-on compute costs outside Aurora:

- **No VPC complexity** — Aurora uses the Data API, Lambda connects directly
- **Cost-optimized vectors** — S3 Vectors is ~90% cheaper than OpenSearch/Pinecone
- **Multi-environment** — `dev`, `test`, `prod` from the same Terraform codebase
- **Custom domain on prod** — Route53 + ACM certificate on `kausik-digital-twin.com`

---

## Repository Structure

```
alex/
├── backend/
│   ├── planner/         # Orchestrator Lambda — routes jobs to sub-agents
│   ├── tagger/          # Instrument classification agent
│   ├── reporter/        # Portfolio analysis report agent
│   ├── charter/         # Chart data generation agent
│   ├── retirement/      # Retirement projection agent
│   ├── researcher/      # Autonomous market research (App Runner)
│   ├── ingest/          # Document ingestion Lambda
│   ├── database/        # Shared database library + migrations
│   └── api/             # FastAPI backend for frontend
│
├── frontend/            # NextJS React application
│
├── infra/               # Unified Terraform (CI/CD)
│   ├── bootstrap/       # S3 state bucket + DynamoDB locks
│   ├── modules/         # sagemaker, ingestion, database, agents, frontend
│   ├── environments/    # dev.tfvars, test.tfvars, prod.tfvars
│   └── main.tf
│
├── terraform/           # Per-component Terraform (local state)
│   ├── 2_sagemaker/
│   ├── 3_ingestion/
│   ├── 4_researcher/
│   ├── 5_database/
│   ├── 6_agents/
│   ├── 7_frontend/
│   └── 8_enterprise/
│
└── .github/workflows/
    ├── deploy.yml       # One-click deploy to dev / test / prod
    └── destroy.yml      # Destroy with environment confirmation gate
```

---

## Deploying Alex

### Prerequisites

- AWS account with `aiengineer` IAM user (`aws configure`)
- [Docker Desktop](https://www.docker.com/products/docker-desktop/) running
- [uv](https://docs.astral.sh/uv/) — `curl -LsSf https://astral.sh/uv/install.sh | sh`
- Node.js 20+, Terraform 1.7+
- [Clerk](https://clerk.com) account, [LangFuse](https://cloud.langfuse.com) account, [Polygon.io](https://polygon.io) API key

---

### Step 1 — IAM Permissions

```bash
# Follow guides/1_permissions.md
# Creates AlexAccess IAM group with all required service policies
```

---

### Step 2 — SageMaker Embeddings Endpoint

Deploys a serverless SageMaker endpoint running `all-MiniLM-L6-v2` for document embeddings.

```bash
cd terraform/2_sagemaker
cp terraform.tfvars.example terraform.tfvars && vim terraform.tfvars
terraform init && terraform apply
```

---

### Step 3 — Ingestion Pipeline

S3 Vectors bucket + Lambda for document ingestion (~90% cheaper than OpenSearch).

```bash
cd terraform/3_ingestion
cp terraform.tfvars.example terraform.tfvars && vim terraform.tfvars
terraform init && terraform apply
```

---

### Step 4 — Researcher Agent

Autonomous research agent on App Runner with Playwright for web browsing.

```bash
cd backend/researcher && uv run package_docker.py   # Requires Docker

cd terraform/4_researcher
cp terraform.tfvars.example terraform.tfvars && vim terraform.tfvars
terraform init && terraform apply
```

> Enable **Nova Pro** model access in the AWS Bedrock console before deploying.

---

### Step 5 — Aurora Database

Aurora Serverless v2 PostgreSQL with Data API (no VPC needed).

```bash
cd terraform/5_database
cp terraform.tfvars.example terraform.tfvars && vim terraform.tfvars
terraform init && terraform apply

# After cluster reaches "available" (~10 min):
cd backend/database
# Set AURORA_CLUSTER_ARN and AURORA_SECRET_ARN in .env
uv run run_migrations.py    # Creates all tables
uv run seed_data.py         # Loads 22 ETF instruments
```

---

### Step 6 — AI Agent Orchestra

All 5 Lambda agents + SQS queue. This is the core of Alex.

```bash
cd backend && uv run package_docker.py              # Requires Docker

cd terraform/6_agents
cp terraform.tfvars.example terraform.tfvars && vim terraform.tfvars
terraform init && terraform apply

# Test locally (no AWS):
cd backend && MOCK_LAMBDAS=true uv run test_simple.py

# Test on AWS:
cd backend && uv run test_full.py
```

---

### Step 7 — Frontend & API

NextJS frontend + FastAPI Lambda backend + CloudFront CDN.

```bash
cp frontend/.env.local.example frontend/.env.local
# Add NEXT_PUBLIC_CLERK_PUBLISHABLE_KEY

cd terraform/7_frontend
cp terraform.tfvars.example terraform.tfvars && vim terraform.tfvars
terraform init && terraform apply

cd scripts && uv run deploy.py
```

---

### Step 8 — Enterprise Features

CloudWatch dashboards, LangFuse observability, alarms.

```bash
cd terraform/8_enterprise
cp terraform.tfvars.example terraform.tfvars && vim terraform.tfvars
terraform init && terraform apply
```

---

## CI/CD Pipeline

GitHub Actions automates the full deploy/destroy lifecycle across environments.

### How the pipeline works

1. **Package job** — Builds all Lambda zips via Docker (agents, api) and uv (ingest)
2. **Deploy job** — Bootstraps remote state idempotently, runs `terraform plan` + `terraform apply`, then builds and deploys NextJS to S3/CloudFront

### Required GitHub Secrets

| Secret | Description |
|--------|-------------|
| `AWS_ACCESS_KEY_ID` | IAM user access key |
| `AWS_SECRET_ACCESS_KEY` | IAM user secret key |
| `OPENAI_API_KEY` | OpenAI API key |
| `POLYGON_API_KEY` | Polygon.io market data |
| `CLERK_JWKS_URL` | `https://<instance>.clerk.accounts.dev/.well-known/jwks.json` |
| `CLERK_ISSUER` | `https://<instance>.clerk.accounts.dev` |
| `LANGFUSE_PUBLIC_KEY` | LangFuse `pk-lf-...` |
| `LANGFUSE_SECRET_KEY` | LangFuse `sk-lf-...` |
| `NEXT_PUBLIC_CLERK_PUBLISHABLE_KEY` | Clerk publishable key |

### GitHub Environments

| Environment | Rules |
|-------------|-------|
| `dev` | No restrictions — auto deploys |
| `test` | No restrictions — auto deploys |
| `prod` | Required reviewers + wait timer |

**Deploy:** Actions → Deploy Alex → Run workflow → select environment

**Destroy:** Actions → Destroy Alex → Run workflow → type environment name to confirm

---

## Environment Comparison

| Setting | dev | test | prod |
|---------|-----|------|------|
| Aurora max ACU | 1 | 2 | 8 |
| Planner memory | 1024 MB | 2048 MB | 3072 MB |
| Agent memory | 512 MB | 1024 MB | 1024 MB |
| Monitoring | — | Yes | Yes |
| Custom domain | — | — | kausik-digital-twin.com |
| Est. monthly cost | ~$45 | ~$55 | ~$70 |

> Aurora is the largest cost driver (~$43/mo). Destroy when not actively using.

---

## Troubleshooting

### "Failed to sync user: 500" on dashboard

Database schema not applied. Run migrations, and make sure `.env` has the correct `AURORA_CLUSTER_ARN` for the deployed cluster — the scripts use `load_dotenv(override=True)` so the `.env` file takes priority over inline env vars.

```bash
cd backend/database
uv run run_migrations.py && uv run seed_data.py
```

---

### Analysis completes but shows no data

The Planner defaults to calling `alex-reporter` but deployed functions are named `alex-dev-reporter` (environment-prefixed). Ensure these env vars are set on the Planner Lambda:

| Variable | Value |
|----------|-------|
| `REPORTER_FUNCTION` | `alex-<env>-reporter` |
| `CHARTER_FUNCTION` | `alex-<env>-charter` |
| `RETIREMENT_FUNCTION` | `alex-<env>-retirement` |
| `TAGGER_FUNCTION` | `alex-<env>-tagger` |

These are set automatically by the `infra/` Terraform and CI/CD pipeline.

---

### Docker packaging PermissionError

Docker installs Lambda dependencies as root. The `package_docker.py` scripts use `TemporaryDirectory(delete=False)` to skip cleanup. If you see a `Mounts Denied` error, add `/tmp` to Docker Desktop's shared paths: **Settings → Resources → File Sharing**.

---

### Terraform plan: "one of filename,image_uri,s3_bucket must be specified"

Lambda packages haven't been built yet. All `infra/` Lambda functions use S3-based deployment — build first:

```bash
cd backend && uv run package_docker.py          # agents
cd backend/api && uv run package_docker.py      # api
cd backend/ingest && uv sync && uv run package.py  # ingest
```

---

### Bedrock: "Access denied" or "Model not found"

Enable **Nova Pro** in the Bedrock console → **Model access**. For cross-region inference profiles, enable access in every region the profile covers. LiteLLM requires `AWS_REGION_NAME` specifically (not `AWS_REGION`) — set by Terraform automatically.

---

### Aurora: "relation does not exist"

Verify `.env` points to the correct cluster, then re-run migrations:

```bash
aws rds describe-db-clusters \
  --query 'DBClusters[?contains(DBClusterIdentifier,`alex`)].{ID:DBClusterIdentifier,ARN:DBClusterArn}' \
  --output table
```

---

## Built By

**Kausik** — [kausik-digital-twin.com](https://kausik-digital-twin.com) | [GitHub](https://github.com/chatkausik/Alex-AI-Financial-Advisor)
