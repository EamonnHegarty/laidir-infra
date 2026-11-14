# A Lambda function whose CODE is owned by another repo (laidir-api CI runs
# `aws lambda update-function-code`). Terraform owns everything else.

data "archive_file" "placeholder" {
  type        = "zip"
  output_path = "${path.module}/.build/${var.name}.zip"

  source {
    filename = "index.mjs"
    content  = <<-JS
      // Placeholder deployed by Terraform. Real code is shipped by laidir-api CI.
      export const handler = async () => ({
        statusCode: 503,
        headers: { "content-type": "application/json" },
        body: JSON.stringify({ message: "${var.name}: code not deployed yet" }),
      });
    JS
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

resource "aws_iam_role" "this" {
  name                 = "${var.name}-lambda"
  assume_role_policy   = data.aws_iam_policy_document.assume.json
  permissions_boundary = var.permissions_boundary_arn
}

resource "aws_cloudwatch_log_group" "this" {
  #checkov:skip=CKV_AWS_158:AWS-owned encryption for logs; a CMK costs ~$1/month.
  #checkov:skip=CKV_AWS_338:Short retention on purpose: cheaper and less personal data kept.
  name              = "/aws/lambda/${var.name}"
  retention_in_days = var.log_retention_days
}

data "aws_iam_policy_document" "logs" {
  statement {
    sid       = "WriteOwnLogs"
    actions   = ["logs:CreateLogStream", "logs:PutLogEvents"]
    resources = ["${aws_cloudwatch_log_group.this.arn}:*"]
  }
}

data "aws_iam_policy_document" "combined" {
  source_policy_documents = compact([data.aws_iam_policy_document.logs.json, var.policy_json])
}

resource "aws_iam_role_policy" "this" {
  name   = "${var.name}-permissions"
  role   = aws_iam_role.this.id
  policy = data.aws_iam_policy_document.combined.json
}

resource "aws_lambda_function" "this" {
  #checkov:skip=CKV_AWS_50:X-Ray tracing is optional; enable via tracing_mode when needed (cost).
  #checkov:skip=CKV_AWS_115:Reserved concurrency is not set: new accounts can have a total limit of 10. Throttling is done at API Gateway.
  #checkov:skip=CKV_AWS_116:Invoked synchronously by API Gateway; a DLQ only applies to async invocations.
  #checkov:skip=CKV_AWS_117:No VPC: the function only calls public AWS APIs, and a VPC would need a NAT Gateway (~35 EUR/month).
  #checkov:skip=CKV_AWS_173:Environment variables hold no secrets (table name, pool ID); AWS-owned key encryption applies.
  #checkov:skip=CKV_AWS_272:Code signing does not fit update-function-code from CI at this scale.
  function_name = var.name
  description   = var.description
  role          = aws_iam_role.this.arn

  runtime       = var.runtime
  architectures = ["arm64"]
  handler       = "index.handler"
  memory_size   = var.memory_size
  timeout       = var.timeout

  filename         = data.archive_file.placeholder.output_path
  source_code_hash = data.archive_file.placeholder.output_base64sha256

  environment {
    variables = var.environment
  }

  logging_config {
    log_format = "JSON"
    log_group  = aws_cloudwatch_log_group.this.name
  }

  tracing_config {
    mode = var.tracing_mode
  }

  # Code is deployed by laidir-api CI. Without this, every apply would roll it back to the placeholder.
  lifecycle {
    ignore_changes = [filename, source_code_hash]
  }

  depends_on = [aws_iam_role_policy.this]
}
