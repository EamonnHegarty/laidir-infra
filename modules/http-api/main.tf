# API Gateway HTTP API in front of the two Lambdas.
#
#   GET  /health                                  api  (no auth)
#   ANY  /v1/{proxy+}                             api  (Cognito JWT authorizer)
#   ANY  /mcp                                     mcp  (token validated in Lambda, see below)
#   GET  /.well-known/oauth-protected-resource*   mcp  (public metadata, RFC 9728)
#
# /mcp deliberately has no gateway authorizer: Claude only starts OAuth when it gets
# a 401 carrying `WWW-Authenticate: Bearer resource_metadata="..."`, and the HTTP API
# JWT authorizer returns a bare 401. The MCP Lambda verifies the Cognito JWT itself.

resource "aws_apigatewayv2_api" "this" {
  name          = var.name
  protocol_type = "HTTP"
  description   = "Láidir REST API and MCP endpoint."
}

resource "aws_apigatewayv2_authorizer" "cognito" {
  api_id           = aws_apigatewayv2_api.this.id
  name             = "cognito"
  authorizer_type  = "JWT"
  identity_sources = ["$request.header.Authorization"]

  # For Cognito access tokens, API Gateway checks the `client_id` claim against the audience list.
  jwt_configuration {
    issuer   = var.jwt_issuer
    audience = var.jwt_audience
  }
}

# ---------------------------------------------------------------------------
# Integrations
# ---------------------------------------------------------------------------
resource "aws_apigatewayv2_integration" "api" {
  api_id                 = aws_apigatewayv2_api.this.id
  integration_type       = "AWS_PROXY"
  integration_uri        = var.api_function.invoke_arn
  payload_format_version = "2.0"
}

resource "aws_apigatewayv2_integration" "mcp" {
  api_id                 = aws_apigatewayv2_api.this.id
  integration_type       = "AWS_PROXY"
  integration_uri        = var.mcp_function.invoke_arn
  payload_format_version = "2.0"
}

# ---------------------------------------------------------------------------
# Routes
# ---------------------------------------------------------------------------
resource "aws_apigatewayv2_route" "health" {
  #checkov:skip=CKV_AWS_309:Health check is intentionally public.
  api_id    = aws_apigatewayv2_api.this.id
  route_key = "GET /health"
  target    = "integrations/${aws_apigatewayv2_integration.api.id}"
}

resource "aws_apigatewayv2_route" "v1" {
  api_id             = aws_apigatewayv2_api.this.id
  route_key          = "ANY /v1/{proxy+}"
  target             = "integrations/${aws_apigatewayv2_integration.api.id}"
  authorization_type = "JWT"
  authorizer_id      = aws_apigatewayv2_authorizer.cognito.id
}

resource "aws_apigatewayv2_route" "mcp" {
  #checkov:skip=CKV_AWS_309:Auth is enforced in the MCP Lambda so it can return the 401 + WWW-Authenticate header Claude requires.
  api_id    = aws_apigatewayv2_api.this.id
  route_key = "ANY /mcp"
  target    = "integrations/${aws_apigatewayv2_integration.mcp.id}"
}

resource "aws_apigatewayv2_route" "protected_resource_metadata" {
  #checkov:skip=CKV_AWS_309:OAuth protected resource metadata must be public (RFC 9728).
  for_each = toset([
    "GET /.well-known/oauth-protected-resource",
    "GET /.well-known/oauth-protected-resource/{proxy+}",
  ])

  api_id    = aws_apigatewayv2_api.this.id
  route_key = each.value
  target    = "integrations/${aws_apigatewayv2_integration.mcp.id}"
}

# ---------------------------------------------------------------------------
# Stage: throttling is the main cost guard rail against abuse.
# ---------------------------------------------------------------------------
resource "aws_cloudwatch_log_group" "access" {
  #checkov:skip=CKV_AWS_158:AWS-owned encryption for logs; a CMK costs ~$1/month.
  #checkov:skip=CKV_AWS_338:Short retention on purpose: cheaper and less personal data kept.
  # Must match the apply role's scoped pattern /aws/apigateway/laidir-<env>-*
  name              = "/aws/apigateway/${var.name}-access"
  retention_in_days = var.log_retention_days
}

resource "aws_apigatewayv2_stage" "default" {
  api_id      = aws_apigatewayv2_api.this.id
  name        = "$default"
  auto_deploy = true

  # Default limits apply to each route individually (authenticated /v1 traffic).
  default_route_settings {
    throttling_burst_limit = var.throttling_burst_limit
    throttling_rate_limit  = var.throttling_rate_limit
  }

  # Tighter limits on routes that reach a Lambda WITHOUT a gateway auth check,
  # which caps what anonymous traffic can cost.
  dynamic "route_settings" {
    for_each = var.public_route_throttling
    content {
      route_key              = route_settings.key
      throttling_burst_limit = route_settings.value.burst
      throttling_rate_limit  = route_settings.value.rate
    }
  }

  # Route settings fail if the route doesn't exist yet.
  depends_on = [
    aws_apigatewayv2_route.health,
    aws_apigatewayv2_route.mcp,
    aws_apigatewayv2_route.protected_resource_metadata,
  ]

  access_log_settings {
    destination_arn = aws_cloudwatch_log_group.access.arn
    format = jsonencode({
      requestId          = "$context.requestId"
      ip                 = "$context.identity.sourceIp"
      requestTime        = "$context.requestTime"
      routeKey           = "$context.routeKey"
      status             = "$context.status"
      responseLength     = "$context.responseLength"
      integrationLatency = "$context.integrationLatency"
      integrationError   = "$context.integrationErrorMessage"
      authorizerError    = "$context.authorizer.error"
      sub                = "$context.authorizer.claims.sub"
    })
  }
}

# ---------------------------------------------------------------------------
# Allow API Gateway to invoke the functions (this API only).
# ---------------------------------------------------------------------------
resource "aws_lambda_permission" "api" {
  statement_id  = "AllowHttpApiInvoke"
  action        = "lambda:InvokeFunction"
  function_name = var.api_function.name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.this.execution_arn}/*/*"
}

resource "aws_lambda_permission" "mcp" {
  statement_id  = "AllowHttpApiInvoke"
  action        = "lambda:InvokeFunction"
  function_name = var.mcp_function.name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.this.execution_arn}/*/*"
}
