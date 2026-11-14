variable "name" {
  description = "Table name, e.g. laidir-prod-data."
  type        = string
}

variable "deletion_protection" {
  description = "Block table deletion (DeleteTable fails until this is turned off)."
  type        = bool
  default     = true
}

variable "point_in_time_recovery" {
  description = "Continuous backups with 35-day point-in-time restore. Costs ~$0.20/GB-month, negligible at personal scale."
  type        = bool
  default     = true
}
