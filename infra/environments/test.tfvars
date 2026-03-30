# ── Test Environment ─────────────────────────────────────────────────────────
# Mirrors production sizing for integration / QA testing
environment    = "test"
aws_region     = "us-east-1"
bedrock_region = "us-west-2"

# Database
aurora_min_capacity = 0.5
aurora_max_capacity = 2.0

# Agents
planner_memory = 2048
agent_memory   = 1024

# Bedrock
bedrock_model_id = "us.amazon.nova-pro-v1:0"
polygon_plan     = "free"

# Monitoring enabled in test
enable_monitoring = true

# No custom domain in test (can add a subdomain if wanted)
custom_domain       = ""
acm_certificate_arn = ""

# Scheduler off
scheduler_enabled = false

# Lambda packages path
lambda_packages_dir = "../backend"
