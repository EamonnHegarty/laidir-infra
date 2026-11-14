variable "name" {
  description = "IAM role name."
  type        = string
}

variable "description" {
  description = "IAM role description."
  type        = string
  default     = ""
}

variable "oidc_provider_arn" {
  description = "ARN of the token.actions.githubusercontent.com OIDC provider in this account."
  type        = string
}

variable "subjects" {
  description = "Exact OIDC `sub` claims allowed to assume the role, e.g. `repo:Owner/repo:environment:prod`."
  type        = list(string)

  validation {
    condition     = length(var.subjects) > 0 && alltrue([for s in var.subjects : startswith(s, "repo:") && !strcontains(s, "*")])
    error_message = "Subjects must be explicit `repo:...` claims with no wildcards."
  }
}

variable "managed_policy_arns" {
  description = "Managed policy ARNs to attach."
  type        = list(string)
  default     = []
}

variable "inline_policies" {
  description = "Map of inline policy name => JSON policy document."
  type        = map(string)
  default     = {}
}

variable "max_session_duration" {
  description = "Maximum session duration in seconds."
  type        = number
  default     = 3600
}
