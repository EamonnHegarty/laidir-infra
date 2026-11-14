variable "name" {
  description = "Name prefix, e.g. laidir-prod."
  type        = string
}

variable "alert_email" {
  description = "Email subscribed to the alerts topic (AWS sends a confirmation email first)."
  type        = string
  sensitive   = true
}

variable "function_names" {
  description = "Lambda function names to monitor."
  type        = list(string)
}

variable "api_id" {
  description = "HTTP API ID to monitor."
  type        = string
}

variable "table_name" {
  description = "DynamoDB table name to monitor."
  type        = string
}
