variable "name" {
  description = "Name prefix, e.g. laidir-prod."
  type        = string
}

variable "user_pool_tier" {
  description = "Cognito feature plan: LITE, ESSENTIALS or PLUS. Lite and Essentials include 10k free MAU; Essentials adds managed login v2."
  type        = string
  default     = "ESSENTIALS"

  validation {
    condition     = contains(["LITE", "ESSENTIALS", "PLUS"], var.user_pool_tier)
    error_message = "user_pool_tier must be LITE, ESSENTIALS or PLUS."
  }
}

variable "deletion_protection" {
  description = "Prevent the user pool from being deleted."
  type        = bool
  default     = true
}

variable "allow_self_signup" {
  description = "Let anyone create an account from the sign-in page. Turn off to invite users manually."
  type        = bool
  default     = true
}

variable "domain_prefix" {
  description = "Cognito hosted domain prefix. Defaults to <name>-<hash of account id>."
  type        = string
  default     = null
}

variable "mobile_callback_urls" {
  description = "OAuth redirect URIs for the mobile app (custom scheme)."
  type        = list(string)
  default     = ["laidir://auth/callback"]
}

variable "mobile_logout_urls" {
  description = "Sign-out redirect URIs for the mobile app."
  type        = list(string)
  default     = ["laidir://auth/logout"]
}

variable "claude_client_confidential" {
  description = "Generate a client secret for the Claude client (for a directory listing with Anthropic-held credentials). Changing it replaces the client."
  type        = bool
  default     = false
}

variable "devtools_client" {
  description = "Create a public PKCE client with a localhost redirect, for testing the API with real tokens from a laptop."
  type        = bool
  default     = false
}

variable "devtools_callback_urls" {
  description = "Redirect URIs for the devtools client. Must match the laidir-api `pnpm token` script exactly (port included)."
  type        = list(string)
  default     = ["http://localhost:8976/callback"]

  validation {
    condition     = alltrue([for u in var.devtools_callback_urls : startswith(u, "http://localhost:")])
    error_message = "Devtools callback URLs must be http://localhost:<port>/... loopback URLs."
  }
}

variable "devtools_logout_urls" {
  description = "Sign-out redirect URIs for the devtools client."
  type        = list(string)
  default     = ["http://localhost:8976/logout"]
}

variable "ses_email_identity_arn" {
  description = "ARN of a verified SES identity to send auth emails from. Null uses Cognito's default sender (~50 emails/day)."
  type        = string
  default     = null
}

variable "ses_from_address" {
  description = "From address when using SES, e.g. \"Láidir <no-reply@example.com>\"."
  type        = string
  default     = null
}
