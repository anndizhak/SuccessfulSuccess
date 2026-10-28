# Sign-in for the meetings site (was infra/auth.yml): a Cognito user pool with
# email + password self sign-up and Google federation, a public OAuth client
# for the static frontend, and managed login (version 2) on a prefix domain.

resource "aws_cognito_user_pool" "main" {
  name = "${var.project_name}-users"

  # Managed login needs Essentials; the first 10,000 monthly users are free.
  user_pool_tier = "ESSENTIALS"

  # People sign in with their email; there is no separate username.
  # Changing this forces a new pool, which would delete every account.
  username_attributes      = ["email"]
  auto_verified_attributes = ["email"]

  username_configuration {
    case_sensitive = false
  }

  # Self sign-up is on: anyone can create an account.
  admin_create_user_config {
    allow_admin_create_user_only = false
  }

  password_policy {
    minimum_length                   = 8
    require_lowercase                = true
    require_uppercase                = true
    require_numbers                  = true
    require_symbols                  = false
    temporary_password_validity_days = 7
  }

  account_recovery_setting {
    recovery_mechanism {
      name     = "verified_email"
      priority = 1
    }
  }

  # Cognito's built-in sender: 50 emails a day per account, enough for a lab.
  email_configuration {
    email_sending_account = "COGNITO_DEFAULT"
  }


  # The pool holds every account that signed up. A plan that would destroy
  # it stops with an error instead.
  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_cognito_identity_provider" "google" {
  user_pool_id  = aws_cognito_user_pool.main.id
  provider_name = "Google"
  provider_type = "Google"

  provider_details = {
    client_id        = var.google_client_id
    client_secret    = var.google_client_secret
    authorize_scopes = "openid email profile"
  }

  # Without the mapping a Google user arrives with no email. Cognito adds
  # username = sub for Google by itself.
  attribute_mapping = {
    email          = "email"
    email_verified = "email_verified"
    name           = "name"
    username       = "sub"
  }

  # Cognito fills in Google's endpoints itself; they are not ours to manage.
  lifecycle {
    ignore_changes = [
      provider_details["attributes_url"],
      provider_details["attributes_url_add_attributes"],
      provider_details["authorize_url"],
      provider_details["oidc_issuer"],
      provider_details["token_request_method"],
      provider_details["token_url"],
    ]
  }
}

resource "aws_cognito_user_pool_client" "web" {
  name         = "${var.project_name}-web"
  user_pool_id = aws_cognito_user_pool.main.id

  # A public client: a browser cannot keep a secret, so PKCE protects the
  # code exchange instead.
  allowed_oauth_flows_user_pool_client = true
  allowed_oauth_flows                  = ["code"]
  allowed_oauth_scopes                 = ["openid", "email", "profile"]

  # A plain reference, so Terraform creates Google first. No DependsOn needed.
  supported_identity_providers = ["COGNITO", aws_cognito_identity_provider.google.provider_name]

  callback_urls       = var.callback_urls
  logout_urls         = var.logout_urls
  explicit_auth_flows = ["ALLOW_REFRESH_TOKEN_AUTH"]

  # Sign-in errors do not reveal whether an email has an account.
  prevent_user_existence_errors = "ENABLED"
}

resource "aws_cognito_user_pool_domain" "main" {
  domain                = var.domain_prefix
  user_pool_id          = aws_cognito_user_pool.main.id
  managed_login_version = 2
}

# A version 2 domain has no sign-in page until the client has a branding: the
# site's Canva look. The colours are in branding/settings.json, the three
# images are branding/*.svg.
resource "aws_cognito_managed_login_branding" "web" {
  user_pool_id = aws_cognito_user_pool.main.id
  client_id    = aws_cognito_user_pool_client.web.id

  settings = jsonencode(jsondecode(file("${path.module}/branding/settings.json")))

  asset {
    category   = "FORM_LOGO"
    color_mode = "LIGHT"
    extension  = "SVG"
    bytes      = filebase64("${path.module}/branding/form-logo.svg")
  }

  asset {
    category   = "PAGE_HEADER_LOGO"
    color_mode = "LIGHT"
    extension  = "SVG"
    bytes      = filebase64("${path.module}/branding/page-header-logo.svg")
  }

  asset {
    category   = "PAGE_BACKGROUND"
    color_mode = "LIGHT"
    extension  = "SVG"
    bytes      = filebase64("${path.module}/branding/page-background.svg")
  }

  depends_on = [aws_cognito_user_pool_domain.main]
}
