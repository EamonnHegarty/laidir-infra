locals {
  env  = "prod"
  name = "laidir-${local.env}"
}

# Created by global/. Every workload role must carry it, or the CI apply role can't create it.
data "aws_iam_policy" "workload_boundary" {
  name = "laidir-workload-boundary"
}

module "table" {
  source = "../../modules/data-table"

  name                   = "${local.name}-data"
  deletion_protection    = true
  point_in_time_recovery = true
}

module "auth" {
  source = "../../modules/auth"

  name                = local.name
  user_pool_tier      = "ESSENTIALS"
  deletion_protection = true
  # Self sign-up is open, but the signup function only lets it through from the app's client and
  # while there are fewer than local.max_users accounts. Invites (admin-create-user) still work.
  allow_self_signup          = true
  pre_sign_up_lambda_arn     = module.signup_function.arn
  mobile_callback_urls       = var.mobile_callback_urls
  mobile_logout_urls         = var.mobile_logout_urls
  claude_client_confidential = var.claude_client_confidential
  # Laptop testing of /v1 with real tokens (laidir-api `pnpm token`, Bruno collection).
  devtools_client = true
}

# Both functions get the same table access (no Scan). Tenant isolation is
# enforced in code: PK is always derived from the verified token's `sub`.
data "aws_iam_policy_document" "table_access" {
  statement {
    sid = "AppTable"
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
    resources = [module.table.arn, module.table.index_arns]
  }
}

# The api function also handles DELETE /v1/account: sign the caller out everywhere, then delete
# their Cognito user (after their data). Only on this pool; the code only ever passes the token's sub.
data "aws_iam_policy_document" "api_access" {
  source_policy_documents = [data.aws_iam_policy_document.table_access.json]

  statement {
    sid = "AccountDeletion"
    actions = [
      "cognito-idp:AdminUserGlobalSignOut",
      "cognito-idp:AdminDeleteUser",
    ]
    resources = [module.auth.user_pool_arn]
  }
}

locals {
  common_env = {
    TABLE_NAME     = module.table.name
    COGNITO_ISSUER = module.auth.issuer
    USER_POOL_ID   = module.auth.user_pool_id
    STAGE          = local.env
  }
}

module "api_function" {
  source = "../../modules/lambda-function"

  name                     = "${local.name}-api"
  description              = "Láidir REST API (/v1). Code deployed by laidir-api CI."
  permissions_boundary_arn = data.aws_iam_policy.workload_boundary.arn
  policy_json              = data.aws_iam_policy_document.api_access.json
  log_retention_days       = 30

  environment = merge(local.common_env, {
    MOBILE_CLIENT_ID   = module.auth.mobile_client_id
    DEVTOOLS_CLIENT_ID = module.auth.devtools_client_id
  })
}

module "mcp_function" {
  source = "../../modules/lambda-function"

  name                     = "${local.name}-mcp"
  description              = "Láidir MCP server for the Claude connector. Code deployed by laidir-api CI."
  permissions_boundary_arn = data.aws_iam_policy.workload_boundary.arn
  policy_json              = data.aws_iam_policy_document.table_access.json
  log_retention_days       = 30
  timeout                  = 29 # just under API Gateway's 30s integration limit

  # The MCP URL is derived from the request at runtime (requestContext.domainName),
  # which avoids a dependency cycle between this function and the API.
  environment = merge(local.common_env, {
    CLAUDE_CLIENT_ID = module.auth.claude_client_id
    AUTH_DOMAIN      = module.auth.auth_domain
  })
}

# Pre sign-up check for Cognito. The allowed client is passed by NAME, not ID: the ID would make a
# cycle (pool -> this function -> client -> pool). The function looks the name up at sign-up time.
locals {
  max_users = 30
}

module "signup_function" {
  source = "../../modules/lambda-function"

  name                     = "${local.name}-signup"
  description              = "Cognito pre sign-up check: app client only, at most ${local.max_users} accounts. Code deployed by laidir-api CI."
  permissions_boundary_arn = data.aws_iam_policy.workload_boundary.arn
  memory_size              = 128
  timeout                  = 5 # Cognito waits at most 5 s for a trigger
  log_retention_days       = 30

  environment = {
    ALLOWED_CLIENT_NAME = "${local.name}-mobile"
    MAX_USERS           = tostring(local.max_users)
  }
}

# Kept out of the module so the pool ARN doesn't feed back into the function (the pool needs its ARN).
data "aws_iam_policy_document" "signup_access" {
  statement {
    sid = "SignupCheck"
    actions = [
      "cognito-idp:DescribeUserPoolClient",
      "cognito-idp:ListUsers",
    ]
    resources = [module.auth.user_pool_arn]
  }
}

resource "aws_iam_role_policy" "signup_access" {
  name   = "${local.name}-signup-cognito"
  role   = module.signup_function.role_name
  policy = data.aws_iam_policy_document.signup_access.json
}

resource "aws_lambda_permission" "cognito_signup" {
  statement_id  = "AllowCognitoPreSignUp"
  action        = "lambda:InvokeFunction"
  function_name = module.signup_function.function_name
  principal     = "cognito-idp.amazonaws.com"
  source_arn    = module.auth.user_pool_arn
}

module "http_api" {
  source = "../../modules/http-api"

  name       = local.name
  jwt_issuer = module.auth.issuer
  # /v1 accepts access tokens issued to the app and to the devtools client (same users, same rules).
  jwt_audience = compact([module.auth.mobile_client_id, module.auth.devtools_client_id])

  api_function = {
    name       = module.api_function.function_name
    invoke_arn = module.api_function.invoke_arn
  }
  mcp_function = {
    name       = module.mcp_function.function_name
    invoke_arn = module.mcp_function.invoke_arn
  }

  log_retention_days = 30
}

# The MCP URL as a Cognito resource server, for RFC 8707 resource binding. Claude sends
# `resource=<mcp_url>` when it signs in; without a resource server with that identifier Cognito
# accepts the authorize request but then refuses the code exchange (invalid_grant). With it,
# Claude's access tokens carry aud = <mcp_url>, which the MCP server checks. No custom scopes.
resource "aws_cognito_resource_server" "mcp" {
  user_pool_id = module.auth.user_pool_id
  identifier   = module.http_api.mcp_url
  name         = "${local.name}-mcp"
}

module "observability" {
  source = "../../modules/observability"

  name           = local.name
  alert_email    = var.alert_email
  function_names = [module.api_function.function_name, module.mcp_function.function_name]
  api_id         = module.http_api.api_id
  table_name     = module.table.name
}

# Cost circuit breaker: if requests flood in, throttle everything to 0 within ~5-10 min.
module "circuit_breaker" {
  source = "../../modules/circuit-breaker"

  name                     = local.name
  api_id                   = module.http_api.api_id
  stage_name               = module.http_api.stage_name
  request_threshold        = 3000
  alerts_topic_arn         = module.observability.alerts_topic_arn
  permissions_boundary_arn = data.aws_iam_policy.workload_boundary.arn
}
