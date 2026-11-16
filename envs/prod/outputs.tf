output "api_endpoint" {
  description = "Base URL of the API. The mobile app uses <endpoint>/v1."
  value       = module.http_api.endpoint
}

output "mcp_url" {
  description = "Paste into Claude: Settings -> Connectors -> Add custom connector."
  value       = module.http_api.mcp_url
}

output "claude_client_id" {
  description = "Paste into the custom connector's advanced settings (OAuth client ID)."
  value       = module.auth.claude_client_id
}

output "mobile_client_id" {
  description = "Cognito app client ID for laidir-mobile."
  value       = module.auth.mobile_client_id
}

output "devtools_client_id" {
  description = "Cognito app client ID for testing /v1 from a laptop (laidir-api `pnpm token`)."
  value       = module.auth.devtools_client_id
}

output "cognito_issuer" {
  description = "OIDC issuer URL."
  value       = module.auth.issuer
}

output "auth_domain" {
  description = "Managed login / OAuth base URL."
  value       = module.auth.auth_domain
}

output "table_name" {
  description = "DynamoDB table name."
  value       = module.table.name
}

output "lambda_function_names" {
  description = "Function names the laidir-api CI deploys code to."
  value = {
    api = module.api_function.function_name
    mcp = module.mcp_function.function_name
  }
}

output "circuit_breaker_alarm" {
  description = "Alarm that trips the cost circuit breaker (see README: Circuit breaker)."
  value       = module.circuit_breaker.alarm_name
}
