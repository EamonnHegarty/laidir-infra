# ---------------------------------------------------------------------------
# CI roles assumed by GitHub Actions via OIDC.
#
#   laidir-gha-infra-plan   PRs on laidir-infra       read-only + state lock
#   laidir-gha-infra-apply  main, environment:<env>   read-only + scoped writes
#   laidir-gha-api-deploy-* laidir-api, env:<env>     UpdateFunctionCode only
# ---------------------------------------------------------------------------

locals {
  infra_repo_full = "${var.github_owner}/${var.infra_repo}"
  api_repo_full   = "${var.github_owner}/${var.api_repo}"

  arn_region = "${var.region}:${var.account_id}"

  # Resource patterns per environment prefix (laidir-prod, ...)
  role_arns        = [for p in local.env_prefixes : "arn:aws:iam::${var.account_id}:role/${p}-*"]
  function_arns    = [for p in local.env_prefixes : "arn:aws:lambda:${local.arn_region}:function:${p}-*"]
  table_arns       = flatten([for p in local.env_prefixes : ["arn:aws:dynamodb:${local.arn_region}:table/${p}-*", "arn:aws:dynamodb:${local.arn_region}:table/${p}-*/index/*"]])
  log_group_arns   = flatten([for p in local.env_prefixes : ["arn:aws:logs:${local.arn_region}:log-group:/aws/lambda/${p}-*", "arn:aws:logs:${local.arn_region}:log-group:/aws/lambda/${p}-*:*", "arn:aws:logs:${local.arn_region}:log-group:/aws/apigateway/${p}-*", "arn:aws:logs:${local.arn_region}:log-group:/aws/apigateway/${p}-*:*"]])
  alarm_arns       = [for p in local.env_prefixes : "arn:aws:cloudwatch:${local.arn_region}:alarm:${p}-*"]
  topic_arns       = [for p in local.env_prefixes : "arn:aws:sns:${local.arn_region}:${p}-*"]
  state_env_prefix = [for env in var.environments : "${local.state_arn}/envs/${env}/*"]
}

# ---------------------------------------------------------------------------
# Shared deny: neither CI role may read user data or PII, even though
# ReadOnlyAccess would otherwise allow it. Terraform never needs item-level reads.
# ---------------------------------------------------------------------------
data "aws_iam_policy_document" "deny_user_data" {
  statement {
    sid    = "DenyAppDataReads"
    effect = "Deny"
    actions = [
      "dynamodb:GetItem",
      "dynamodb:BatchGetItem",
      "dynamodb:Query",
      "dynamodb:Scan",
      "dynamodb:PartiQLSelect",
      "dynamodb:GetRecords",
      "dynamodb:ExportTableToPointInTime",
      "cognito-idp:ListUsers",
      "cognito-idp:ListUsersInGroup",
      "cognito-idp:AdminGetUser",
      "cognito-idp:AdminListDevices",
      "cognito-idp:AdminListGroupsForUser",
      "logs:GetLogEvents",
      "logs:FilterLogEvents",
      "logs:StartQuery",
      "logs:StartLiveTail",
    ]
    resources = ["*"]
  }

  statement {
    sid           = "DenyObjectReadsOutsideState"
    effect        = "Deny"
    actions       = ["s3:GetObject", "s3:GetObjectVersion"]
    not_resources = ["${local.state_arn}/*"]
  }
}

# State access: read everything (plan needs other roots' outputs in future),
# write only lock files + the env state objects.
data "aws_iam_policy_document" "state_plan" {
  statement {
    sid       = "ListStateBucket"
    actions   = ["s3:ListBucket"]
    resources = [local.state_arn]
  }

  statement {
    sid       = "ReadState"
    actions   = ["s3:GetObject"]
    resources = ["${local.state_arn}/*"]
  }

  statement {
    sid       = "StateLockFiles"
    actions   = ["s3:PutObject", "s3:DeleteObject"]
    resources = ["${local.state_arn}/*.tflock"]
  }
}

data "aws_iam_policy_document" "state_apply" {
  statement {
    sid       = "ListStateBucket"
    actions   = ["s3:ListBucket"]
    resources = [local.state_arn]
  }

  statement {
    sid       = "ReadWriteEnvState"
    actions   = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"]
    resources = local.state_env_prefix
  }
}

# ---------------------------------------------------------------------------
# Apply role write permissions, scoped to laidir-<env>-* names wherever the
# service supports resource-level permissions.
# ---------------------------------------------------------------------------
data "aws_iam_policy_document" "apply_writes" {
  statement {
    sid    = "DynamoDBTables"
    effect = "Allow"
    actions = [
      "dynamodb:CreateTable",
      "dynamodb:UpdateTable",
      "dynamodb:DeleteTable",
      "dynamodb:TagResource",
      "dynamodb:UntagResource",
      "dynamodb:UpdateContinuousBackups",
      "dynamodb:UpdateTimeToLive",
    ]
    resources = local.table_arns
  }

  statement {
    sid    = "LambdaFunctions"
    effect = "Allow"
    actions = [
      "lambda:CreateFunction",
      "lambda:DeleteFunction",
      "lambda:UpdateFunctionConfiguration",
      "lambda:UpdateFunctionCode",
      "lambda:AddPermission",
      "lambda:RemovePermission",
      "lambda:PutFunctionConcurrency",
      "lambda:DeleteFunctionConcurrency",
      "lambda:TagResource",
      "lambda:UntagResource",
    ]
    resources = local.function_arns
  }

  # Workload roles may only be created/changed if they carry the boundary.
  statement {
    sid    = "WorkloadRolesWithBoundary"
    effect = "Allow"
    actions = [
      "iam:CreateRole",
      "iam:PutRolePermissionsBoundary",
      "iam:AttachRolePolicy",
      "iam:DetachRolePolicy",
      "iam:PutRolePolicy",
      "iam:DeleteRolePolicy",
    ]
    resources = local.role_arns
    condition {
      test     = "StringEquals"
      variable = "iam:PermissionsBoundary"
      values   = [aws_iam_policy.workload_boundary.arn]
    }
  }

  statement {
    sid    = "WorkloadRolesHousekeeping"
    effect = "Allow"
    actions = [
      "iam:DeleteRole",
      "iam:UpdateRole",
      "iam:UpdateRoleDescription",
      "iam:UpdateAssumeRolePolicy",
      "iam:TagRole",
      "iam:UntagRole",
    ]
    resources = local.role_arns
  }

  statement {
    sid       = "PassWorkloadRolesToLambda"
    effect    = "Allow"
    actions   = ["iam:PassRole"]
    resources = local.role_arns
    condition {
      test     = "StringEquals"
      variable = "iam:PassedToService"
      values   = ["lambda.amazonaws.com"]
    }
  }

  statement {
    sid    = "ProtectBoundary"
    effect = "Deny"
    actions = [
      "iam:DeleteRolePermissionsBoundary",
      "iam:CreatePolicyVersion",
      "iam:DeletePolicy",
      "iam:DeletePolicyVersion",
      "iam:SetDefaultPolicyVersion",
    ]
    resources = ["*"]
  }

  statement {
    sid    = "LogGroups"
    effect = "Allow"
    actions = [
      "logs:CreateLogGroup",
      "logs:DeleteLogGroup",
      "logs:PutRetentionPolicy",
      "logs:DeleteRetentionPolicy",
      "logs:TagResource",
      "logs:UntagResource",
      "logs:TagLogGroup",
      "logs:UntagLogGroup",
    ]
    resources = local.log_group_arns
  }

  # API Gateway access logging uses log deliveries, which have no resource-level scoping.
  statement {
    sid    = "ApiGatewayAccessLogDelivery"
    effect = "Allow"
    actions = [
      "logs:CreateLogDelivery",
      "logs:GetLogDelivery",
      "logs:UpdateLogDelivery",
      "logs:DeleteLogDelivery",
      "logs:ListLogDeliveries",
      "logs:PutResourcePolicy",
      "logs:DescribeResourcePolicies",
    ]
    resources = ["*"]
  }

  # HTTP API ARNs contain a generated ID, so these can only be scoped to the region.
  statement {
    sid       = "HttpApis"
    effect    = "Allow"
    actions   = ["apigateway:GET", "apigateway:POST", "apigateway:PUT", "apigateway:PATCH", "apigateway:DELETE", "apigateway:TagResource", "apigateway:UntagResource"]
    resources = ["arn:aws:apigateway:${var.region}::/apis", "arn:aws:apigateway:${var.region}::/apis/*", "arn:aws:apigateway:${var.region}::/tags/*"]
  }

  # CreateUserPool cannot be scoped before the pool exists.
  statement {
    sid       = "CognitoCreatePool"
    effect    = "Allow"
    actions   = ["cognito-idp:CreateUserPool"]
    resources = ["*"]
  }

  statement {
    sid    = "CognitoManagePools"
    effect = "Allow"
    actions = [
      "cognito-idp:UpdateUserPool",
      "cognito-idp:DeleteUserPool",
      "cognito-idp:SetUserPoolMfaConfig",
      "cognito-idp:CreateUserPoolClient",
      "cognito-idp:UpdateUserPoolClient",
      "cognito-idp:DeleteUserPoolClient",
      "cognito-idp:CreateUserPoolDomain",
      "cognito-idp:UpdateUserPoolDomain",
      "cognito-idp:DeleteUserPoolDomain",
      "cognito-idp:CreateManagedLoginBranding",
      "cognito-idp:UpdateManagedLoginBranding",
      "cognito-idp:DeleteManagedLoginBranding",
      "cognito-idp:TagResource",
      "cognito-idp:UntagResource",
    ]
    resources = ["arn:aws:cognito-idp:${local.arn_region}:userpool/*"]
  }

  statement {
    sid    = "Alarms"
    effect = "Allow"
    actions = [
      "cloudwatch:PutMetricAlarm",
      "cloudwatch:DeleteAlarms",
      "cloudwatch:TagResource",
      "cloudwatch:UntagResource",
    ]
    resources = local.alarm_arns
  }

  statement {
    sid    = "AlertTopics"
    effect = "Allow"
    actions = [
      "sns:CreateTopic",
      "sns:DeleteTopic",
      "sns:SetTopicAttributes",
      "sns:Subscribe",
      "sns:Unsubscribe",
      "sns:TagResource",
      "sns:UntagResource",
    ]
    resources = local.topic_arns
  }
}

# ---------------------------------------------------------------------------
# Roles
# ---------------------------------------------------------------------------
module "infra_plan_role" {
  source = "../modules/github-oidc-role"

  name              = "${local.prefix}-gha-infra-plan"
  description       = "Read-only plan for pull requests on ${local.infra_repo_full}."
  oidc_provider_arn = aws_iam_openid_connect_provider.github.arn
  subjects          = ["repo:${local.infra_repo_full}:pull_request"]

  managed_policy_arns = ["arn:aws:iam::aws:policy/ReadOnlyAccess"]
  inline_policies = {
    deny-user-data = data.aws_iam_policy_document.deny_user_data.json
    state          = data.aws_iam_policy_document.state_plan.json
  }
}

module "infra_apply_role" {
  source = "../modules/github-oidc-role"

  name              = "${local.prefix}-gha-infra-apply"
  description       = "Apply on merge to main for ${local.infra_repo_full}, gated by GitHub Environments."
  oidc_provider_arn = aws_iam_openid_connect_provider.github.arn
  subjects          = [for env in var.environments : "repo:${local.infra_repo_full}:environment:${env}"]

  managed_policy_arns = ["arn:aws:iam::aws:policy/ReadOnlyAccess"]
  inline_policies = {
    deny-user-data = data.aws_iam_policy_document.deny_user_data.json
    state          = data.aws_iam_policy_document.state_apply.json
    writes         = data.aws_iam_policy_document.apply_writes.json
  }
}

data "aws_iam_policy_document" "api_deploy" {
  for_each = toset(var.environments)

  statement {
    sid    = "UpdateLambdaCodeOnly"
    effect = "Allow"
    actions = [
      "lambda:UpdateFunctionCode",
      "lambda:GetFunction",
      "lambda:GetFunctionConfiguration",
    ]
    resources = [for fn in var.lambda_functions : "arn:aws:lambda:${local.arn_region}:function:${local.prefix}-${each.key}-${fn}"]
  }
}

module "api_deploy_role" {
  source   = "../modules/github-oidc-role"
  for_each = toset(var.environments)

  name              = "${local.prefix}-gha-api-deploy-${each.key}"
  description       = "Lets ${local.api_repo_full} update Lambda code in ${each.key} (and nothing else)."
  oidc_provider_arn = aws_iam_openid_connect_provider.github.arn
  subjects          = ["repo:${local.api_repo_full}:environment:${each.key}"]

  inline_policies = {
    update-function-code = data.aws_iam_policy_document.api_deploy[each.key].json
  }
}
