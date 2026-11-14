variable "name" {
  description = "Function name, e.g. laidir-prod-api."
  type        = string
}

variable "description" {
  description = "Function description."
  type        = string
  default     = ""
}

variable "runtime" {
  description = "Lambda runtime. nodejs24.x is supported until at least April 2028."
  type        = string
  default     = "nodejs24.x"
}

variable "memory_size" {
  description = "Memory in MB (CPU scales with it)."
  type        = number
  default     = 256
}

variable "timeout" {
  description = "Timeout in seconds. API Gateway HTTP APIs cut off at 30s anyway."
  type        = number
  default     = 10
}

variable "environment" {
  description = "Environment variables (non-secret configuration only)."
  type        = map(string)
  default     = {}
}

variable "policy_json" {
  description = "Extra IAM policy JSON for the execution role (e.g. DynamoDB access). Logs access is always added."
  type        = string
  default     = ""
}

variable "permissions_boundary_arn" {
  description = "Permissions boundary for the execution role. Required by the CI apply role."
  type        = string
}

variable "log_retention_days" {
  description = "CloudWatch log retention in days."
  type        = number
  default     = 14
}

variable "tracing_mode" {
  description = "X-Ray tracing mode: PassThrough (off) or Active."
  type        = string
  default     = "PassThrough"
}
