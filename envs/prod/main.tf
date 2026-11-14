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

  name                       = local.name
  user_pool_tier             = "ESSENTIALS"
  deletion_protection        = true
  allow_self_signup          = true
  mobile_callback_urls       = var.mobile_callback_urls
  mobile_logout_urls         = var.mobile_logout_urls
  claude_client_confidential = var.claude_client_confidential
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
  policy_json              = data.aws_iam_policy_document.table_access.json
  log_retention_days       = 30

  environment = merge(local.common_env, {
    MOBILE_CLIENT_ID = module.auth.mobile_client_id
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

module "http_api" {
  source = "../../modules/http-api"

  name         = local.name
  jwt_issuer   = module.auth.issuer
  jwt_audience = [module.auth.mobile_client_id]

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

module "observability" {
  source = "../../modules/observability"

  name           = local.name
  alert_email    = var.alert_email
  function_names = [module.api_function.function_name, module.mcp_function.function_name]
  api_id         = module.http_api.api_id
  table_name     = module.table.name
}
