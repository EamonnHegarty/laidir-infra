output "github_oidc_provider_arn" {
  description = "ARN of the GitHub Actions OIDC provider."
  value       = aws_iam_openid_connect_provider.github.arn
}

output "workload_boundary_arn" {
  description = "ARN of the permissions boundary every workload role must carry. Passed to envs/* as an input."
  value       = aws_iam_policy.workload_boundary.arn
}

output "infra_plan_role_arn" {
  description = "Set as GitHub repo variable AWS_PLAN_ROLE_ARN on laidir-infra."
  value       = module.infra_plan_role.arn
}

output "infra_apply_role_arn" {
  description = "Set as GitHub repo variable AWS_APPLY_ROLE_ARN on laidir-infra."
  value       = module.infra_apply_role.arn
}

output "api_deploy_role_arns" {
  description = "Per-environment roles for the laidir-api repo (set as AWS_DEPLOY_ROLE_ARN in its GitHub Environments)."
  value       = { for env, m in module.api_deploy_role : env => m.arn }
}
