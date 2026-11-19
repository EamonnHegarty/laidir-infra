variable "region" {
  description = "Primary AWS region."
  type        = string
  default     = "eu-west-1"
}

variable "account_id" {
  description = "The workload AWS account ID (the `fitness` member account). Terraform refuses to run anywhere else."
  type        = string
  default     = "670518205160"
}

variable "github_owner" {
  description = "GitHub user that owns the repos trusted via OIDC. Personal account only."
  type        = string
  default     = "EamonnHegarty"
}

variable "github_owner_id" {
  description = "Numeric GitHub user ID of github_owner (used in immutable OIDC subjects)."
  type        = number
  default     = 91144434
}

variable "infra_repo_id" {
  description = "Numeric GitHub repository ID of the infra repo (immutable OIDC subject)."
  type        = number
  default     = 1457972060
}

variable "api_repo_id" {
  description = "Numeric GitHub repository ID of the API repo (immutable OIDC subject)."
  type        = number
  default     = 1458628544
}

variable "infra_repo" {
  description = "Name of this Terraform repo."
  type        = string
  default     = "laidir-infra"
}

variable "api_repo" {
  description = "Name of the API repo whose CI deploys Lambda code."
  type        = string
  default     = "laidir-api"
}

variable "environments" {
  description = "Deployable environments. Each gets resource prefix `laidir-<env>` and a GitHub Environment of the same name."
  type        = list(string)
  default     = ["prod"]
}

variable "lambda_functions" {
  description = "Short names of the Lambda functions per environment that the API repo may update (full name: laidir-<env>-<fn>)."
  type        = list(string)
  default     = ["api", "mcp", "signup"]
}

variable "alert_email" {
  description = "Email address that receives AWS Budgets notifications. Set in terraform.tfvars (gitignored)."
  type        = string
  sensitive   = true
}

variable "monthly_budget_usd" {
  description = "Monthly cost budget for this account in USD (AWS Budgets bills in USD; 5 USD is roughly 4.50 EUR)."
  type        = number
  default     = 5
}
