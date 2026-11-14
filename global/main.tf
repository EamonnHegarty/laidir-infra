# Account-wide resources, applied manually by a human (not by CI):
#   - GitHub OIDC identity provider
#   - permissions boundary for every workload role
#   - CI roles (plan / apply / API code deploy)
#   - account budget
#
# CI cannot modify this root: the apply role has no permissions on `laidir-gha-*`
# roles or on the boundary policy, so it can never widen its own access.

locals {
  prefix       = "laidir"
  env_prefixes = [for env in var.environments : "${local.prefix}-${env}"]
  state_arn    = "arn:aws:s3:::laidir-tfstate-${var.account_id}"
}

resource "aws_iam_openid_connect_provider" "github" {
  url            = "https://token.actions.githubusercontent.com"
  client_id_list = ["sts.amazonaws.com"]
  # AWS validates GitHub's certificate via its own trusted CA store, so no thumbprint is required.
}

# ---------------------------------------------------------------------------
# Permissions boundary: the ceiling for every role Terraform creates for
# workloads (Lambda execution roles). Even if a role's own policy is too broad,
# it can never exceed this.
# ---------------------------------------------------------------------------
data "aws_iam_policy_document" "workload_boundary" {
  statement {
    sid    = "Logs"
    effect = "Allow"
    actions = [
      "logs:CreateLogStream",
      "logs:PutLogEvents",
    ]
    resources = flatten([
      for p in local.env_prefixes : "arn:aws:logs:${var.region}:${var.account_id}:log-group:/aws/lambda/${p}-*:*"
    ])
  }

  statement {
    sid    = "AppTable"
    effect = "Allow"
    actions = [
      "dynamodb:GetItem",
      "dynamodb:BatchGetItem",
      "dynamodb:Query",
      "dynamodb:PutItem",
      "dynamodb:UpdateItem",
      "dynamodb:DeleteItem",
      "dynamodb:BatchWriteItem",
      "dynamodb:ConditionCheckItem",
    ]
    resources = flatten([
      for p in local.env_prefixes : [
        "arn:aws:dynamodb:${var.region}:${var.account_id}:table/${p}-*",
        "arn:aws:dynamodb:${var.region}:${var.account_id}:table/${p}-*/index/*",
      ]
    ])
  }

  statement {
    sid       = "Tracing"
    effect    = "Allow"
    actions   = ["xray:PutTraceSegments", "xray:PutTelemetryRecords"]
    resources = ["*"]
  }
}

resource "aws_iam_policy" "workload_boundary" {
  name        = "${local.prefix}-workload-boundary"
  description = "Permissions boundary for all Laidir workload roles (Lambda execution roles)."
  policy      = data.aws_iam_policy_document.workload_boundary.json
}
