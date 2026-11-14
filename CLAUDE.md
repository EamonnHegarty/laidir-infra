# CLAUDE.md: laidir-infra

Terraform for Láidir (workout tracker + Claude MCP connector). Sibling repos: `laidir-api`, `laidir-mobile`.

## Hard rules
- **GitHub:** only ever act on repos owned by `EamonnHegarty`. Never touch any org (especially Phorest).
- **AWS:** never run `terraform apply`, `destroy`, `import`, `state` commands or anything that changes AWS.
  Locally run only `terraform fmt`, `terraform init -backend=false`, `terraform validate`. The human applies.
- **No long-lived credentials anywhere.** Humans use SSO (`AWS_PROFILE=fitness-admin`); CI uses GitHub OIDC.
- **Cost target is about €0/month.** No NAT Gateway, ALB, RDS, VPC, provisioned or always-on compute, or customer-managed KMS keys
  without an explicit decision.
- Commits are small and logically grouped; the author is the user, with a `Co-Authored-By: Claude` trailer.
- Changes reach `main` only through PRs; CI plans on the PR and applies prod on merge.

## Accounts
- Workload account `fitness` = `670518205160` (member of org `o-8ed84urxl1`, OU `Workloads`). Region `eu-west-1`.
- Every provider sets `allowed_account_ids = ["670518205160"]`. Keep it.
- Management account `347038623770` is billing and governance only. Nothing in this repo targets it.

## Data model rules (must hold from day one, multi-tenant)
- Every record is keyed by the Cognito user ID (`sub`): `PK = USER#<sub>`. Tenant isolation is enforced in
  Lambda code (the execution role is shared), so the key must always come from the verified token, never the request body.
- IDs are client-generated UUIDs; every item has `updated_at` (ISO-8601 UTC) and `deleted_at` (soft delete), for offline sync.
- Workout and routine JSON is versioned (`schema_version`); the schema lives in `laidir-api` and is shared by REST and MCP.
- See `docs/access-patterns.md` before changing keys or indexes.

## Structure
- `bootstrap/`: state bucket, local state then migrated. Human-applied.
- `global/`: OIDC provider, CI roles, permissions boundary, budget. Human-applied; CI cannot modify it.
- `modules/`: one concern per module. `envs/prod/`: composition, applied by CI.
- Workload resources are named `laidir-<env>-*`; the CI apply role's permissions are scoped to that prefix.
- Workload IAM roles must set `permissions_boundary` to the `laidir-workload-boundary` policy, or the apply role can't create them.
- Lambda code is owned by `laidir-api` CI (`update-function-code`); Terraform ignores `filename` and `source_code_hash`.

## Conventions
- Checkov exceptions are inline: `#checkov:skip=<ID>:<reason>`. Always give a reason.
- Variables and outputs need descriptions (tflint enforces this).
- Verify Cognito, API Gateway and free-tier details against current AWS and provider docs rather than memory.
