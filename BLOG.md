# Building Alex: A Production Multi-Agent AI Financial Advisor on AWS

*How I designed, built, and deployed an enterprise-grade agentic SaaS platform — from a blank AWS account to a live production URL.*

---

## The Idea

Most AI demos are toys. A chatbot that answers questions, a notebook that calls an API, a weekend project that works on localhost and nowhere else. I wanted to build something real — a system that handles real users, real data, real infrastructure, and real production concerns.

The result is **Alex** — an AI financial advisor that analyzes equity portfolios through a coordinated team of specialized AI agents. Users sign in, connect their portfolio, and Alex dispatches five agents that work in parallel to produce a full analysis: a written report, interactive charts, and a retirement projection.

**Live at:** [kausik-digital-twin.com](https://kausik-digital-twin.com)

---

## What Alex Does

When a user triggers an analysis, Alex:

1. Fetches live prices for every instrument in the portfolio via Polygon.io
2. Tags each instrument with asset class, sector, and geographic classification
3. Runs three specialized agents **in parallel** — a report writer, a chart generator, and a retirement specialist
4. Saves all results to Aurora and streams them to the frontend as they arrive

The output is three tabs of AI-generated insights:

- **Overview** — narrative portfolio analysis, risk assessment, concentration alerts, and personalized recommendations
- **Charts** — allocation breakdown, sector exposure, and performance visualization
- **Retirement Projection** — Monte Carlo simulation of long-term wealth trajectory based on the user's stated goals

---

## Architecture

The system is fully serverless on AWS. There is no always-on compute outside the database.

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
                                                 └──────┴─────────────┘
                                                              │
                                                     Aurora Serverless v2
```

### The Request Flow

1. User clicks "Run Analysis" in the NextJS frontend
2. FastAPI Lambda validates the Clerk JWT, creates a job record in Aurora, and sends a message to SQS
3. SQS triggers the **Planner Lambda** via event source mapping
4. Planner fetches portfolio data and live prices, then invokes Reporter, Charter, and Retirement Lambdas in parallel
5. Each agent runs its analysis and writes its payload back to Aurora
6. The frontend polls until all three payloads are present, then renders the results

---

## The Agent System

Each agent is an independent AWS Lambda function built on the **OpenAI Agents SDK** with **LiteLLM** routing requests to **AWS Bedrock Nova Pro**.

### Why OpenAI Agents SDK + Bedrock?

The OpenAI Agents SDK is the cleanest abstraction for building tool-using agents — clean APIs for structured outputs, function tools, context passing, and tracing. By pairing it with LiteLLM, I can point it at any model without changing agent code. Bedrock Nova Pro gives strong reasoning at reasonable cost without the rate limit problems of other providers.

One important constraint: due to a current LiteLLM/Bedrock limitation, **an agent cannot use both structured outputs and tool calling simultaneously**. Each agent is designed around one or the other:

| Agent | Mode | Why |
|-------|------|-----|
| Planner | Tools | Needs to call Reporter, Charter, Retirement as tools |
| Tagger | Structured Output | Clean JSON classification, no tools needed |
| Reporter | Tools | Reads portfolio data from DB during generation |
| Charter | Structured Output | Deterministic chart data schema |
| Retirement | Structured Output | Deterministic projection schema |

### The Planner (Orchestrator)

The Planner is the most complex agent. It receives the job from SQS, enriches the portfolio data with live prices and instrument classifications, and then uses function tools to invoke the three specialist agents. The Bedrock model decides the orchestration sequence — it can invoke agents in any order or combination based on what the portfolio needs.

```python
agent = Agent[PlannerContext](
    name="Financial Planner",
    instructions=PLANNER_INSTRUCTIONS,
    model=model,
    tools=[invoke_tagger, invoke_reporter, invoke_charter, invoke_retirement]
)

result = await Runner.run(agent, input=task, context=context, max_turns=20)
```

### Context Passing

For agents that need to know which user's data to read, I use the OpenAI Agents SDK's `RunContextWrapper` pattern — a typed context object that travels with the agent through all tool calls:

```python
@function_tool
async def get_portfolio_data(
    wrapper: RunContextWrapper[ReporterContext], symbols: List[str]
) -> str:
    db = wrapper.context.db
    user_id = wrapper.context.clerk_user_id
    return await db.get_positions(user_id, symbols)
```

This avoids the antipattern of baking user identity into prompts or environment variables.

---

## Infrastructure Design Decisions

### No VPC

Aurora Serverless v2 with the **Data API** enabled means Lambda functions connect to the database over HTTPS without any VPC configuration. No private subnets, no NAT gateways, no security group headaches. For a project where developer velocity matters, this is a major win.

### S3 Vectors for Embeddings

The Researcher agent (App Runner service with Playwright) stores market research as embeddings for retrieval by other agents. I chose **AWS S3 Vectors** over OpenSearch or Pinecone — roughly **90% cheaper** at the scale this project operates, and deeply integrated with IAM. The tradeoff is fewer query primitives, but cosine similarity search is all this use case needs.

### Lambda for Everything

All five agents run as Lambda functions — even the long-running Planner, which has a 900-second timeout. The cold start cost is acceptable because analyses are user-triggered, not latency-sensitive background tasks. Lambda's per-invocation billing means the infrastructure costs near zero when no analyses are running.

### Three Environments, One Codebase

The `infra/` directory contains a unified Terraform configuration that deploys to `dev`, `test`, or `prod` via a single variable file. All three environments share the same modules — differences are just resource sizing:

| | dev | test | prod |
|--|-----|------|------|
| Aurora max ACU | 1 | 2 | 8 |
| Planner memory | 1024 MB | 2048 MB | 3072 MB |
| Custom domain | — | — | kausik-digital-twin.com |
| Est. monthly cost | ~$45 | ~$55 | ~$70 |

---

## CI/CD Pipeline

Deploying Alex is a single GitHub Actions workflow run. It:

1. **Packages** all 7 Lambda functions — five agents and the API Lambda are built with Docker for `linux/amd64`, the ingest Lambda uses a pure Python zip
2. **Bootstraps** remote Terraform state idempotently (S3 bucket + DynamoDB lock table) using AWS CLI existence checks — no Terraform state needed for the bootstrap itself
3. **Applies** the full Terraform plan
4. **Builds** the NextJS static export with environment-specific API URLs injected at build time
5. **Deploys** the frontend to S3 and invalidates the CloudFront cache

Total run time: ~15 minutes for a full deploy including Lambda packaging.

### The Docker Packaging Problem

One unexpected challenge: Docker installs Lambda dependencies as `root`, which means Python's `TemporaryDirectory` cleanup raises a `PermissionError` when it tries to `chmod` root-owned files. The fix is simple but non-obvious — `TemporaryDirectory(delete=False)` skips cleanup entirely. The CI runner workspace is ephemeral anyway.

### Artifact Path Stripping

`upload-artifact@v4` may strip the common directory prefix when uploading multiple files. All Lambda zips live under `backend/`, so the artifact can land at `./ingest/lambda_function.zip` instead of `./backend/ingest/lambda_function.zip`. The deploy workflow includes an explicit path-fix step that detects and corrects this before Terraform runs.

---

## Observability

Every agent run is traced in **LangFuse** — model inputs, outputs, token counts, latency, and tool calls are all captured. This makes it practical to debug agent misbehavior in production without drowning in CloudWatch logs.

```python
with trace("Planner Agent"):
    result = await Runner.run(agent, input=task, context=context)
```

LangFuse is initialized at Lambda cold start. If credentials are missing or invalid, the agents continue normally — observability is a non-blocking enhancement, not a dependency.

---

## Hard Problems I Solved

### Function Name Environment Variables

The Planner invokes sub-agents by Lambda function name. The default in code is `alex-reporter`, but the deployed function is `alex-dev-reporter` (or `alex-prod-reporter`). I solved this by injecting `REPORTER_FUNCTION`, `CHARTER_FUNCTION`, `RETIREMENT_FUNCTION`, and `TAGGER_FUNCTION` as environment variables from Terraform, set to `${local.prefix}-reporter` etc. The code reads them at runtime — no hardcoded names anywhere.

### Terraform `fileexists()` at Plan Time

Terraform's `fileexists()` is evaluated during `terraform plan`, not `terraform apply`. If you guard a Lambda resource with `filename = fileexists(zip) ? zip : null`, Terraform rejects it at plan time because `null` means none of `filename/image_uri/s3_bucket` are specified. The fix: switch to **S3-based Lambda deployment** using `aws_s3_object` with a `count = fileexists(...) ? 1 : 0` guard, then always reference `s3_bucket` + `s3_key` on the Lambda resource. Plan succeeds regardless of whether the zip exists on disk.

### `load_dotenv(override=True)` Foot Gun

The database migration script uses `load_dotenv(override=True)` — which means `.env` file values override inline environment variables set before the script runs. Running `AURORA_CLUSTER_ARN=prod-arn uv run run_migrations.py` silently migrates the wrong cluster if `.env` has a different ARN. Always check `.env` before running migrations.

### CloudFront CNAME Conflict on Prod Deploy

A previous manual deployment had attached the custom domain to a different CloudFront distribution. Terraform's `CreateDistributionWithTags` fails with `CNAMEAlreadyExists` when another distribution holds the same alias. Fix: use `aws cloudfront update-distribution` to remove the aliases from the old distribution first, then re-run the Terraform deploy.

---

## What I'd Do Differently

**Automate database migrations in the CI pipeline.** Currently migrations are a manual step after each environment's first deploy. It would be straightforward to add a Lambda-based migration runner invoked by a Terraform `null_resource` after the cluster is available.

**Use `load_dotenv(override=False)` in scripts.** Environment variables explicitly set by the caller should win over `.env` defaults. `override=True` inverts this and causes hard-to-debug cross-environment contamination.

**Remote state from day one.** The per-guide Terraform directories use local state, which is fine for learning but painful when you need to share outputs across modules. The unified `infra/` directory with remote S3 state is the right architecture — I'd start there.

---

## The Stack, Summarized

| Concern | Choice | Why |
|---------|--------|-----|
| LLM | Bedrock Nova Pro | Cost-effective, no rate limits, AWS-native |
| Agent framework | OpenAI Agents SDK | Clean tool-use API, good tracing |
| LLM adapter | LiteLLM | Route any model without code changes |
| Compute | AWS Lambda | Per-invocation billing, no idle cost |
| Database | Aurora Serverless v2 | Data API = no VPC, scales to zero |
| Vectors | S3 Vectors | 90% cheaper than alternatives |
| Auth | Clerk | JWT validation in Lambda, handles all user management |
| Frontend | NextJS static export | Deployable to S3, no server needed |
| CDN | CloudFront | Global distribution, custom domain via ACM |
| IaC | Terraform | Full infrastructure reproducibility |
| CI/CD | GitHub Actions | One workflow for build + deploy + destroy |
| Observability | LangFuse | Agent-level tracing without custom instrumentation |

---

## Try It

The platform is live at **[kausik-digital-twin.com](https://kausik-digital-twin.com)**. Sign in with Clerk, add a portfolio, and run an analysis.

The full source is on GitHub: **[github.com/chatkausik/Alex-AI-Financial-Advisor](https://github.com/chatkausik/Alex-AI-Financial-Advisor)**

Clone it, add your API keys to GitHub Actions, and you can have your own instance running in about 20 minutes.

---

*Built by Kausik — [kausik-digital-twin.com](https://kausik-digital-twin.com)*
