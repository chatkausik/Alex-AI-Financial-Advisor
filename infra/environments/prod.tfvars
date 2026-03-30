# ── Production Environment ───────────────────────────────────────────────────
# Full resources, custom domain, monitoring, all features on
environment    = "prod"
aws_region     = "us-east-1"
bedrock_region = "us-west-2"

# Database - allow scaling up for production load
aurora_min_capacity = 0.5
aurora_max_capacity = 8.0

# Agents - full memory allocation
planner_memory = 3072
agent_memory   = 1024

# Bedrock
bedrock_model_id = "us.amazon.nova-pro-v1:0"
polygon_plan     = "free"  # change to "paid" if upgrading

# Monitoring always on in prod
enable_monitoring = true

# Custom domain — fill in your domain and cert ARN
custom_domain       = "kausik-digital-twin.com"
acm_certificate_arn = "arn:aws:acm:us-east-1:937991583343:certificate/e82c8eeb-1c09-435a-8f74-8974931ecbd5"

# Scheduler for automated research
scheduler_enabled = false  # enable when ready

# Lambda packages path
lambda_packages_dir = "../backend"
