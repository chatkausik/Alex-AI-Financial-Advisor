# Alex Unified Infrastructure

Single Terraform root that deploys the complete Alex platform (Guides 1–8) to any environment.

## Directory Structure

```
infra/
├── bootstrap/          # One-time: creates S3 state bucket + DynamoDB lock table
├── modules/
│   ├── sagemaker/      # Guide 2 – HuggingFace embedding endpoint
│   ├── ingestion/      # Guide 3 – S3 Vectors + ingest Lambda + API Gateway
│   ├── database/       # Guide 5 – Aurora Serverless v2 PostgreSQL
│   ├── agents/         # Guide 6 – 5 Lambda agents + SQS orchestration
│   ├── frontend/       # Guide 7 – CloudFront + S3 + API Gateway + API Lambda
│   └── monitoring/     # Guide 8 – CloudWatch dashboards + alarms
├── environments/
│   ├── dev.tfvars      # Minimal (0.5–1 ACU, 512 MB Lambda, no monitoring)
│   ├── test.tfvars     # Medium  (0.5–2 ACU, 1024 MB Lambda, monitoring on)
│   └── prod.tfvars     # Full    (0.5–8 ACU, 3072 MB Planner, custom domain)
├── main.tf             # Root module — calls all sub-modules
├── variables.tf        # All input variables
├── outputs.tf          # All outputs including deployment_summary
└── versions.tf         # Provider versions + S3 backend (partial config)
```

## First-Time Setup

### 1. Bootstrap remote state (run ONCE per AWS account)

```bash
cd infra/bootstrap
terraform init
terraform apply
```

### 2. Set secrets (sensitive vars — never commit these)

Export or use a `.env` file:

```bash
export TF_VAR_openai_api_key="sk-proj-..."
export TF_VAR_polygon_api_key="AC9Kg..."
export TF_VAR_clerk_jwks_url="https://your-app.clerk.accounts.dev/.well-known/jwks.json"
export TF_VAR_langfuse_public_key="pk-lf-..."
export TF_VAR_langfuse_secret_key="sk-lf-..."
```

### 3. Package Lambda functions

```bash
cd backend
uv run package_docker.py       # packages all 5 agents
cd api && uv run package_docker.py  # packages API Lambda
```

### 4. Init and deploy

```bash
cd infra
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
ENV=dev   # or test / prod

terraform init \
  -backend-config="bucket=alex-terraform-state-${ACCOUNT_ID}" \
  -backend-config="key=${ENV}/terraform.tfstate" \
  -backend-config="region=us-east-1" \
  -backend-config="dynamodb_table=alex-terraform-locks"

terraform apply -var-file="environments/${ENV}.tfvars"
```

## Deploy via CI/CD (GitHub Actions)

Go to **Actions → Deploy Alex → Run workflow**, select environment, click Run.

Required GitHub Secrets:

| Secret | Description |
|--------|-------------|
| `AWS_ACCESS_KEY_ID` | IAM user access key |
| `AWS_SECRET_ACCESS_KEY` | IAM user secret key |
| `OPENAI_API_KEY` | OpenAI key for LangFuse tracing |
| `POLYGON_API_KEY` | Polygon.io market data key |
| `CLERK_JWKS_URL` | Clerk JWKS endpoint |
| `CLERK_ISSUER` | Clerk issuer URL |
| `LANGFUSE_PUBLIC_KEY` | LangFuse `pk-lf-...` |
| `LANGFUSE_SECRET_KEY` | LangFuse `sk-lf-...` |
| `NEXT_PUBLIC_CLERK_PUBLISHABLE_KEY` | Clerk publishable key |

### GitHub Environments

Create three environments in **Settings → Environments**:

| Environment | Protection |
|-------------|-----------|
| `dev` | None (auto-approve) |
| `test` | None (auto-approve) |
| `prod` | Required reviewers + wait timer |

## Destroy via CI/CD

Go to **Actions → Destroy Alex → Run workflow**, select environment, type the environment name as confirmation.

## Destroy Locally

```bash
cd infra
terraform destroy -var-file="environments/${ENV}.tfvars"
```

## Environment Differences

| Setting | dev | test | prod |
|---------|-----|------|------|
| Aurora max ACU | 1 | 2 | 8 |
| Planner memory | 1024 MB | 2048 MB | 3072 MB |
| Agent memory | 512 MB | 1024 MB | 1024 MB |
| Monitoring | ❌ | ✅ | ✅ |
| Custom domain | ❌ | ❌ | ✅ |
| Estimated cost | ~$45/mo | ~$55/mo | ~$70/mo |

Aurora is the biggest cost driver (~$43/mo baseline). Destroy when not actively developing.
