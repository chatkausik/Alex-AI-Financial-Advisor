# ── Dev Environment ──────────────────────────────────────────────────────────
# Minimal resources to keep costs low during development
environment    = "dev"
aws_region     = "us-east-1"
bedrock_region = "us-west-2"

# Database - smallest possible
aurora_min_capacity = 0.5
aurora_max_capacity = 1.0

# Agents - reduced memory
planner_memory = 1024
agent_memory   = 512

# Bedrock
bedrock_model_id = "us.amazon.nova-pro-v1:0"
polygon_plan     = "free"

# Monitoring - skip in dev to save costs
enable_monitoring = false

# No custom domain in dev
custom_domain       = ""
acm_certificate_arn = ""

# Scheduler off
scheduler_enabled = false

# Lambda packages path (relative to infra/ directory)
lambda_packages_dir = "../backend"
