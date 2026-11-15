# Cost circuit breaker for the HTTP API.
#
#   API request Count > threshold in 5 min  ->  CloudWatch alarm
#     -> SNS (breaker topic)  ->  breaker Lambda sets every route's throttle to 0
#     -> SNS (alerts topic)   ->  email to the owner
#
# Once tripped, the API answers 429 to everything until a human resets it by
# re-running the deploy workflow (Terraform restores the configured throttles).
# Budgets react in hours; this reacts in ~5-10 minutes.

data "aws_region" "current" {}

locals {
  stage_arn = "arn:aws:apigateway:${data.aws_region.current.region}::/apis/${var.api_id}/stages/${var.stage_name}"
}

resource "aws_sns_topic" "trip" {
  #checkov:skip=CKV_AWS_26:CloudWatch alarms can't publish to topics encrypted with the AWS-managed key; a CMK costs ~$1/month. Carries alarm metadata only.
  name = "${var.name}-circuit-breaker"
}

resource "aws_cloudwatch_metric_alarm" "request_flood" {
  alarm_name          = "${var.name}-api-request-flood"
  alarm_description   = "More than ${var.request_threshold} API requests in 5 minutes. The circuit breaker sets all throttles to 0. Reset: see laidir-infra README (Circuit breaker)."
  namespace           = "AWS/ApiGateway"
  metric_name         = "Count"
  dimensions          = { ApiId = var.api_id, Stage = var.stage_name }
  statistic           = "Sum"
  period              = 300
  evaluation_periods  = 1
  comparison_operator = "GreaterThanThreshold"
  threshold           = var.request_threshold
  treat_missing_data  = "notBreaching"

  alarm_actions = [aws_sns_topic.trip.arn, var.alerts_topic_arn]
  ok_actions    = [var.alerts_topic_arn]
}

# ---------------------------------------------------------------------------
# Breaker Lambda (code owned by this repo, unlike the app functions)
# ---------------------------------------------------------------------------
data "archive_file" "breaker" {
  type        = "zip"
  output_path = "${path.module}/.build/${var.name}-circuit-breaker.zip"

  source {
    filename = "index.mjs"
    content  = file("${path.module}/src/index.mjs")
  }
}

data "aws_iam_policy_document" "assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "breaker" {
  name                 = "${var.name}-circuit-breaker-lambda"
  assume_role_policy   = data.aws_iam_policy_document.assume.json
  permissions_boundary = var.permissions_boundary_arn
}

resource "aws_cloudwatch_log_group" "breaker" {
  #checkov:skip=CKV_AWS_158:AWS-owned encryption for logs; a CMK costs ~$1/month.
  #checkov:skip=CKV_AWS_338:Short retention on purpose; trips are also emailed.
  name              = "/aws/lambda/${var.name}-circuit-breaker"
  retention_in_days = 90
}

data "aws_iam_policy_document" "breaker" {
  statement {
    sid       = "WriteOwnLogs"
    actions   = ["logs:CreateLogStream", "logs:PutLogEvents"]
    resources = ["${aws_cloudwatch_log_group.breaker.arn}:*"]
  }

  # Read and update this one stage only (GetStage = GET, UpdateStage = PATCH).
  statement {
    sid       = "ThrottleThisStage"
    actions   = ["apigateway:GET", "apigateway:PATCH"]
    resources = [local.stage_arn]
  }
}

resource "aws_iam_role_policy" "breaker" {
  name   = "${var.name}-circuit-breaker"
  role   = aws_iam_role.breaker.id
  policy = data.aws_iam_policy_document.breaker.json
}

resource "aws_lambda_function" "breaker" {
  #checkov:skip=CKV_AWS_50:X-Ray not needed for a one-call function.
  #checkov:skip=CKV_AWS_115:Reserved concurrency not set: new accounts can have a total limit of 10, and SNS triggers are rare.
  #checkov:skip=CKV_AWS_116:SNS retries failed async invokes; the alarm also emails the owner, so a missed trip is still noticed.
  #checkov:skip=CKV_AWS_117:No VPC: only calls the API Gateway control plane.
  #checkov:skip=CKV_AWS_173:Environment variables hold only the API ID and stage name.
  #checkov:skip=CKV_AWS_272:Code signing does not fit an inline Terraform-managed function.
  function_name = "${var.name}-circuit-breaker"
  description   = "Sets every route's throttle on ${var.name} to 0 when the request-flood alarm fires."
  role          = aws_iam_role.breaker.arn

  runtime       = "nodejs24.x"
  architectures = ["arm64"]
  handler       = "index.handler"
  memory_size   = 128
  timeout       = 30

  filename         = data.archive_file.breaker.output_path
  source_code_hash = data.archive_file.breaker.output_base64sha256

  environment {
    variables = {
      API_ID     = var.api_id
      STAGE_NAME = var.stage_name
    }
  }

  logging_config {
    log_format = "JSON"
    log_group  = aws_cloudwatch_log_group.breaker.name
  }

  depends_on = [aws_iam_role_policy.breaker]
}

resource "aws_lambda_permission" "sns" {
  statement_id  = "AllowCircuitBreakerTopic"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.breaker.function_name
  principal     = "sns.amazonaws.com"
  source_arn    = aws_sns_topic.trip.arn
}

resource "aws_sns_topic_subscription" "breaker" {
  topic_arn = aws_sns_topic.trip.arn
  protocol  = "lambda"
  endpoint  = aws_lambda_function.breaker.arn

  depends_on = [aws_lambda_permission.sns]
}
