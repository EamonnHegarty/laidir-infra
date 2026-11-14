variable "region" {
  description = "AWS region."
  type        = string
  default     = "eu-west-1"
}

variable "account_id" {
  description = "Workload account ID. Terraform refuses to run anywhere else."
  type        = string
  default     = "670518205160"
}

variable "alert_email" {
  description = "Email for CloudWatch alarm notifications. In CI this comes from the ALERT_EMAIL secret."
  type        = string
  sensitive   = true
}

variable "mobile_callback_urls" {
  description = "OAuth redirect URIs for the mobile app."
  type        = list(string)
  default     = ["laidir://auth/callback"]
}

variable "mobile_logout_urls" {
  description = "Sign-out redirect URIs for the mobile app."
  type        = list(string)
  default     = ["laidir://auth/logout"]
}

variable "claude_client_confidential" {
  description = "Switch the Claude client to confidential (for a Claude directory listing). Replaces the client."
  type        = bool
  default     = false
}
