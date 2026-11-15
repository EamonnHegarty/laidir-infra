output "api_id" {
  description = "HTTP API ID."
  value       = aws_apigatewayv2_api.this.id
}

output "endpoint" {
  description = "Base URL of the API (default execute-api domain)."
  value       = aws_apigatewayv2_api.this.api_endpoint
}

output "mcp_url" {
  description = "MCP server URL to paste into Claude's custom connector dialog."
  value       = "${aws_apigatewayv2_api.this.api_endpoint}/mcp"
}

output "stage_name" {
  description = "Name of the API stage ($default)."
  value       = aws_apigatewayv2_stage.default.name
}
