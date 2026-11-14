# Cognito user pool with managed login (OAuth 2.0 authorization code + PKCE).
#
# Two app clients:
#   mobile  - the Láidir app (public client, custom-scheme redirect)
#   claude  - Claude's MCP connector. Cognito has no Dynamic Client Registration,
#             so Claude uses this pre-registered client. Public by default (users paste
#             the client ID); set claude_client_confidential = true for a directory
#             listing where Anthropic holds the secret.

data "aws_region" "current" {}
data "aws_caller_identity" "current" {}

locals {
  # Cognito prefix domains are global per region; a short account-derived suffix avoids collisions.
  domain_prefix = coalesce(var.domain_prefix, "${var.name}-${substr(sha1(data.aws_caller_identity.current.account_id), 0, 6)}")

  common_scopes = ["openid", "email", "profile"]
}

resource "aws_cognito_user_pool" "this" {
  name           = var.name
  user_pool_tier = var.user_pool_tier

  deletion_protection = var.deletion_protection ? "ACTIVE" : "INACTIVE"

  username_attributes      = ["email"]
  auto_verified_attributes = ["email"]

  username_configuration {
    case_sensitive = false
  }

  admin_create_user_config {
    allow_admin_create_user_only = !var.allow_self_signup
  }

  password_policy {
    minimum_length                   = 12
    require_lowercase                = true
    require_uppercase                = true
    require_numbers                  = true
    require_symbols                  = false
    temporary_password_validity_days = 7
  }

  mfa_configuration = "OPTIONAL"

  software_token_mfa_configuration {
    enabled = true
  }

  account_recovery_setting {
    recovery_mechanism {
      name     = "verified_email"
      priority = 1
    }
  }

  user_attribute_update_settings {
    attributes_require_verification_before_update = ["email"]
  }

  verification_message_template {
    default_email_option = "CONFIRM_WITH_CODE"
    email_subject        = "Your Láidir verification code"
    email_message        = "Your Láidir verification code is {####}"
  }

  # Default Cognito sender is limited to ~50 emails/day. Switch to SES before going public.
  dynamic "email_configuration" {
    for_each = var.ses_email_identity_arn == null ? [1] : []
    content {
      email_sending_account = "COGNITO_DEFAULT"
    }
  }

  dynamic "email_configuration" {
    for_each = var.ses_email_identity_arn == null ? [] : [1]
    content {
      email_sending_account = "DEVELOPER"
      source_arn            = var.ses_email_identity_arn
      from_email_address    = var.ses_from_address
    }
  }
}

resource "aws_cognito_user_pool_domain" "this" {
  domain                = local.domain_prefix
  user_pool_id          = aws_cognito_user_pool.this.id
  managed_login_version = 2
}

# ---------------------------------------------------------------------------
# App clients
# ---------------------------------------------------------------------------
resource "aws_cognito_user_pool_client" "mobile" {
  name         = "${var.name}-mobile"
  user_pool_id = aws_cognito_user_pool.this.id

  generate_secret = false

  allowed_oauth_flows_user_pool_client = true
  allowed_oauth_flows                  = ["code"]
  allowed_oauth_scopes                 = local.common_scopes
  supported_identity_providers         = ["COGNITO"]
  callback_urls                        = var.mobile_callback_urls
  logout_urls                          = var.mobile_logout_urls

  # Rotation is incompatible with ALLOW_REFRESH_TOKEN_AUTH; refresh goes via /oauth2/token instead.
  explicit_auth_flows = ["ALLOW_USER_SRP_AUTH"]

  refresh_token_rotation {
    feature                    = "ENABLED"
    retry_grace_period_seconds = 10
  }

  access_token_validity  = 60
  id_token_validity      = 60
  refresh_token_validity = 30
  token_validity_units {
    access_token  = "minutes"
    id_token      = "minutes"
    refresh_token = "days"
  }

  enable_token_revocation       = true
  prevent_user_existence_errors = "ENABLED"
}

resource "aws_cognito_user_pool_client" "claude" {
  name         = "${var.name}-claude"
  user_pool_id = aws_cognito_user_pool.this.id

  # Changing this replaces the client (new client ID): users must reconnect the connector.
  generate_secret = var.claude_client_confidential

  allowed_oauth_flows_user_pool_client = true
  allowed_oauth_flows                  = ["code"]
  allowed_oauth_scopes                 = local.common_scopes
  supported_identity_providers         = ["COGNITO"]
  callback_urls                        = ["https://claude.ai/api/mcp/auth_callback"]

  explicit_auth_flows = ["ALLOW_USER_SRP_AUTH"]

  # Claude's connector docs ask public clients to rotate refresh tokens.
  refresh_token_rotation {
    feature                    = "ENABLED"
    retry_grace_period_seconds = 30
  }

  access_token_validity  = 60
  id_token_validity      = 60
  refresh_token_validity = 30
  token_validity_units {
    access_token  = "minutes"
    id_token      = "minutes"
    refresh_token = "days"
  }

  enable_token_revocation       = true
  prevent_user_existence_errors = "ENABLED"
}

# Managed login v2 needs a branding style per client; use Cognito's defaults for now.
resource "aws_cognito_managed_login_branding" "mobile" {
  user_pool_id                = aws_cognito_user_pool.this.id
  client_id                   = aws_cognito_user_pool_client.mobile.id
  use_cognito_provided_values = true
}

resource "aws_cognito_managed_login_branding" "claude" {
  user_pool_id                = aws_cognito_user_pool.this.id
  client_id                   = aws_cognito_user_pool_client.claude.id
  use_cognito_provided_values = true
}
