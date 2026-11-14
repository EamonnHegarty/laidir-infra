variable "name" {
  description = "API name, e.g. laidir-prod."
  type        = string
}

variable "jwt_issuer" {
  description = "Cognito issuer URL for the JWT authorizer."
  type        = string
}

variable "jwt_audience" {
  description = "Allowed app client IDs for /v1 routes (matched against the access token's client_id claim)."
  type        = list(string)
}

variable "api_function" {
  description = "REST API Lambda: name and invoke ARN."
  type = object({
    name       = string
    invoke_arn = string
  })
}

variable "mcp_function" {
  description = "MCP server Lambda: name and invoke ARN."
  type = object({
    name       = string
    invoke_arn = string
  })
}

variable "throttling_burst_limit" {
  description = "Stage-wide burst limit (requests)."
  type        = number
  default     = 20
}

variable "throttling_rate_limit" {
  description = "Stage-wide steady-state rate limit (requests per second)."
  type        = number
  default     = 10
}

variable "log_retention_days" {
  description = "Access log retention in days."
  type        = number
  default     = 14
}
