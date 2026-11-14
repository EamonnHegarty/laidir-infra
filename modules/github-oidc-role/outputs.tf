output "arn" {
  description = "ARN of the role (use as `role-to-assume` in aws-actions/configure-aws-credentials)."
  value       = aws_iam_role.this.arn
}

output "name" {
  description = "Name of the role."
  value       = aws_iam_role.this.name
}
