locals {
  prefix = "${var.project}-${var.environment}"
  tags   = { Project = var.project, Environment = var.environment, ManagedBy = "terraform" }
  agents = ["planner", "tagger", "reporter", "charter", "retirement"]
}

resource "aws_cloudwatch_dashboard" "agents" {
  dashboard_name = "${local.prefix}-agent-performance"

  dashboard_body = jsonencode({
    widgets = [
      {
        type   = "metric"
        width  = 24
        height = 6
        properties = {
          title  = "Agent Execution Duration (ms)"
          region = var.aws_region
          metrics = [
            for a in local.agents : ["AWS/Lambda", "Duration", "FunctionName", "${local.prefix}-${a}", { label = a, stat = "Average" }]
          ]
          view   = "timeSeries"
          period = 300
        }
      },
      {
        type   = "metric"
        width  = 12
        height = 6
        properties = {
          title  = "Agent Invocations"
          region = var.aws_region
          metrics = [
            for a in local.agents : ["AWS/Lambda", "Invocations", "FunctionName", "${local.prefix}-${a}", { label = a, stat = "Sum" }]
          ]
          view   = "timeSeries"
          period = 300
        }
      },
      {
        type   = "metric"
        width  = 12
        height = 6
        properties = {
          title  = "Agent Errors"
          region = var.aws_region
          metrics = [
            for a in local.agents : ["AWS/Lambda", "Errors", "FunctionName", "${local.prefix}-${a}", { label = a, stat = "Sum" }]
          ]
          view   = "timeSeries"
          period = 300
        }
      },
      {
        type   = "metric"
        width  = 12
        height = 6
        properties = {
          title  = "Concurrent Executions"
          region = var.aws_region
          metrics = [
            for a in local.agents : ["AWS/Lambda", "ConcurrentExecutions", "FunctionName", "${local.prefix}-${a}", { label = a, stat = "Maximum" }]
          ]
          view   = "timeSeries"
          period = 300
        }
      }
    ]
  })
}

resource "aws_cloudwatch_dashboard" "ai_models" {
  dashboard_name = "${local.prefix}-ai-model-usage"

  dashboard_body = jsonencode({
    widgets = [
      {
        type   = "metric"
        width  = 12
        height = 6
        properties = {
          title  = "Bedrock Model Invocations"
          region = var.bedrock_region
          metrics = [
            ["AWS/Bedrock", "Invocations", "ModelId", var.bedrock_model_id, { stat = "Sum" }],
            ["AWS/Bedrock", "InvocationClientErrors", "ModelId", var.bedrock_model_id, { stat = "Sum" }],
            ["AWS/Bedrock", "InvocationServerErrors", "ModelId", var.bedrock_model_id, { stat = "Sum" }]
          ]
          view   = "timeSeries"
          period = 300
        }
      },
      {
        type   = "metric"
        width  = 12
        height = 6
        properties = {
          title  = "Bedrock Token Usage"
          region = var.bedrock_region
          metrics = [
            ["AWS/Bedrock", "InputTokenCount", "ModelId", var.bedrock_model_id, { stat = "Sum", label = "Input Tokens" }],
            ["AWS/Bedrock", "OutputTokenCount", "ModelId", var.bedrock_model_id, { stat = "Sum", label = "Output Tokens" }]
          ]
          view   = "timeSeries"
          period = 300
        }
      },
      {
        type   = "metric"
        width  = 12
        height = 6
        properties = {
          title  = "Bedrock Response Latency"
          region = var.bedrock_region
          metrics = [
            ["AWS/Bedrock", "InvocationLatency", "ModelId", var.bedrock_model_id, { stat = "Average", label = "Avg" }],
            ["AWS/Bedrock", "InvocationLatency", "ModelId", var.bedrock_model_id, { stat = "p99", label = "p99" }]
          ]
          view   = "timeSeries"
          period = 300
        }
      },
      {
        type   = "metric"
        width  = 12
        height = 6
        properties = {
          title  = "SageMaker Endpoint Invocations"
          region = var.aws_region
          metrics = [
            [{ expression = "SEARCH('{AWS/SageMaker,EndpointName} MetricName=\"Invocations\"', 'Sum', 300)", id = "m1", label = "Invocations" }]
          ]
          view   = "timeSeries"
          period = 300
        }
      }
    ]
  })
}

# CloudWatch Alarms for critical thresholds
resource "aws_cloudwatch_metric_alarm" "planner_errors" {
  alarm_name          = "${local.prefix}-planner-errors"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "Errors"
  namespace           = "AWS/Lambda"
  period              = 300
  statistic           = "Sum"
  threshold           = 5
  alarm_description   = "Planner agent error rate too high"
  treat_missing_data  = "notBreaching"

  dimensions = { FunctionName = "${local.prefix}-planner" }
  tags       = local.tags
}

resource "aws_cloudwatch_metric_alarm" "api_errors" {
  alarm_name          = "${local.prefix}-api-errors"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "Errors"
  namespace           = "AWS/Lambda"
  period              = 300
  statistic           = "Sum"
  threshold           = 10
  alarm_description   = "API Lambda error rate too high"
  treat_missing_data  = "notBreaching"

  dimensions = { FunctionName = "${local.prefix}-api" }
  tags       = local.tags
}
