# Four alarms per environment, using metric math to combine functions and
# operations so we stay within CloudWatch's 10 free alarms.

resource "aws_sns_topic" "alerts" {
  #checkov:skip=CKV_AWS_26:CloudWatch alarms cannot publish to topics encrypted with the AWS-managed SNS key, and a CMK costs ~$1/month. The topic carries alarm metadata only.
  name = "${var.name}-alerts"
}

resource "aws_sns_topic_subscription" "email" {
  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = var.alert_email
}

locals {
  actions = [aws_sns_topic.alerts.arn]
}

resource "aws_cloudwatch_metric_alarm" "lambda_errors" {
  alarm_name          = "${var.name}-lambda-errors"
  alarm_description   = "Any Lambda invocation errors (unhandled exceptions, timeouts) across ${join(", ", var.function_names)}."
  comparison_operator = "GreaterThanOrEqualToThreshold"
  threshold           = 1
  evaluation_periods  = 1
  treat_missing_data  = "notBreaching"
  alarm_actions       = local.actions
  ok_actions          = local.actions

  metric_query {
    id          = "total"
    expression  = "SUM([${join(",", [for i, _ in var.function_names : "e${i}"])}])"
    label       = "Errors"
    return_data = true
  }

  dynamic "metric_query" {
    for_each = var.function_names
    content {
      id = "e${metric_query.key}"
      metric {
        namespace   = "AWS/Lambda"
        metric_name = "Errors"
        period      = 300
        stat        = "Sum"
        dimensions  = { FunctionName = metric_query.value }
      }
    }
  }
}

resource "aws_cloudwatch_metric_alarm" "lambda_throttles" {
  alarm_name          = "${var.name}-lambda-throttles"
  alarm_description   = "Lambda throttling (concurrency limit hit) across ${join(", ", var.function_names)}."
  comparison_operator = "GreaterThanOrEqualToThreshold"
  threshold           = 1
  evaluation_periods  = 1
  treat_missing_data  = "notBreaching"
  alarm_actions       = local.actions
  ok_actions          = local.actions

  metric_query {
    id          = "total"
    expression  = "SUM([${join(",", [for i, _ in var.function_names : "t${i}"])}])"
    label       = "Throttles"
    return_data = true
  }

  dynamic "metric_query" {
    for_each = var.function_names
    content {
      id = "t${metric_query.key}"
      metric {
        namespace   = "AWS/Lambda"
        metric_name = "Throttles"
        period      = 300
        stat        = "Sum"
        dimensions  = { FunctionName = metric_query.value }
      }
    }
  }
}

resource "aws_cloudwatch_metric_alarm" "api_5xx" {
  alarm_name          = "${var.name}-api-5xx"
  alarm_description   = "HTTP API returned 5 or more server errors in 5 minutes."
  namespace           = "AWS/ApiGateway"
  metric_name         = "5xx"
  dimensions          = { ApiId = var.api_id, Stage = "$default" }
  statistic           = "Sum"
  period              = 300
  evaluation_periods  = 1
  comparison_operator = "GreaterThanOrEqualToThreshold"
  threshold           = 5
  treat_missing_data  = "notBreaching"
  alarm_actions       = local.actions
  ok_actions          = local.actions
}

resource "aws_cloudwatch_metric_alarm" "dynamodb_throttles" {
  alarm_name          = "${var.name}-dynamodb-throttles"
  alarm_description   = "DynamoDB throttled reads or writes on ${var.table_name}."
  comparison_operator = "GreaterThanOrEqualToThreshold"
  threshold           = 1
  evaluation_periods  = 1
  treat_missing_data  = "notBreaching"
  alarm_actions       = local.actions
  ok_actions          = local.actions

  metric_query {
    id          = "total"
    expression  = "r + w"
    label       = "ThrottleEvents"
    return_data = true
  }

  metric_query {
    id = "r"
    metric {
      namespace   = "AWS/DynamoDB"
      metric_name = "ReadThrottleEvents"
      period      = 300
      stat        = "Sum"
      dimensions  = { TableName = var.table_name }
    }
  }

  metric_query {
    id = "w"
    metric {
      namespace   = "AWS/DynamoDB"
      metric_name = "WriteThrottleEvents"
      period      = 300
      stat        = "Sum"
      dimensions  = { TableName = var.table_name }
    }
  }
}
