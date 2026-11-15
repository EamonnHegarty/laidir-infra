variable "name" {
  description = "Name prefix, e.g. laidir-prod."
  type        = string
}

variable "api_id" {
  description = "HTTP API ID to protect."
  type        = string
}

variable "stage_name" {
  description = "Stage to throttle (usually $default)."
  type        = string
}

variable "request_threshold" {
  description = "Trip when the API receives more than this many requests in 5 minutes. Normal use is roughly 100 per 5 minutes."
  type        = number
  default     = 3000
}

variable "alerts_topic_arn" {
  description = "Existing alerts topic (email) that is also notified when the breaker trips and recovers."
  type        = string
}

variable "permissions_boundary_arn" {
  description = "Permissions boundary for the breaker's execution role."
  type        = string
}
