variable "region" {
  description = "AWS region for the state bucket."
  type        = string
  default     = "eu-west-1"
}

variable "account_id" {
  description = "The workload AWS account ID (the `fitness` member account). Terraform refuses to run anywhere else."
  type        = string
  default     = "670518205160"
}

variable "noncurrent_version_retention_days" {
  description = "How long to keep old (noncurrent) versions of state files before S3 expires them."
  type        = number
  default     = 90
}
