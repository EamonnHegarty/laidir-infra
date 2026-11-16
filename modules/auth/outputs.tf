output "user_pool_id" {
  description = "Cognito user pool ID."
  value       = aws_cognito_user_pool.this.id
}

output "user_pool_arn" {
  description = "Cognito user pool ARN."
  value       = aws_cognito_user_pool.this.arn
}

output "issuer" {
  description = "OIDC issuer URL (JWT `iss`). Also the authorization server listed in the MCP protected resource metadata."
  value       = "https://cognito-idp.${data.aws_region.current.region}.amazonaws.com/${aws_cognito_user_pool.this.id}"
}

output "auth_domain" {
  description = "Base URL of the managed login / OAuth endpoints."
  value       = "https://${aws_cognito_user_pool_domain.this.domain}.auth.${data.aws_region.current.region}.amazoncognito.com"
}

output "mobile_client_id" {
  description = "App client ID for the mobile app."
  value       = aws_cognito_user_pool_client.mobile.id
}

output "claude_client_id" {
  description = "App client ID users paste into Claude's custom connector dialog."
  value       = aws_cognito_user_pool_client.claude.id
}

output "devtools_client_id" {
  description = "App client ID for local API testing (null when devtools_client = false)."
  value       = one(aws_cognito_user_pool_client.devtools[*].id)
}

output "claude_client_secret" {
  description = "Claude client secret (only when claude_client_confidential = true)."
  value       = aws_cognito_user_pool_client.claude.client_secret
  sensitive   = true
}
