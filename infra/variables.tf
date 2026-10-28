variable "project_name" {
  type    = string
  default = "successfulsuccess"
}

variable "region" {
  type    = string
  default = "us-east-1"
}

# --- auth (was infra/auth.yml) ----------------------------------------------

variable "domain_prefix" {
  type        = string
  description = "Managed login lives at https://<prefix>.auth.<region>.amazoncognito.com"
}

variable "callback_urls" {
  type        = list(string)
  description = "Where Cognito may send the browser back with a code (trailing slash included)"
}

variable "logout_urls" {
  type        = list(string)
  description = "Where Cognito may send the browser after signing out"
}

variable "google_client_id" {
  type        = string
  description = "OAuth client ID of the Google Cloud web client (public, not a secret)"
}

variable "google_client_secret" {
  type        = string
  sensitive   = true
  description = "Set only in the HCP Terraform workspace, never in a file"
}

# --- reports (was infra/reports.yml) ----------------------------------------

variable "vpc_id" {
  type        = string
  description = "The VPC the backend function and the report builder run in"
}

variable "subnet_ids" {
  type        = list(string)
  description = "The backend function's subnets; the builder runs in the same ones"
}

variable "route_table_ids" {
  type        = list(string)
  description = "Route tables of those subnets; the S3 gateway endpoint adds a route to each"
}

variable "security_group_id" {
  type        = string
  description = "The backend function's security group, which Aurora admits on 5432"
}

variable "architecture" {
  type    = string
  default = "arm64"

  validation {
    condition     = contains(["arm64", "x86_64"], var.architecture)
    error_message = "architecture must be arm64 or x86_64."
  }
}

variable "builder_image_uri" {
  type        = string
  description = "The backend image for the report builder, pinned by digest"
}

variable "db_name" {
  type    = string
  default = "meetings"
}

variable "db_username" {
  type    = string
  default = "app"
}

variable "db_password" {
  type        = string
  sensitive   = true
  description = "Set only in the HCP Terraform workspace, never in a file"
}

variable "app_timezone" {
  type    = string
  default = "Europe/Kyiv"
}

variable "report_email" {
  type        = string
  description = "SES identity: the sender and the only recipient of the report"
}

variable "schedule_expression" {
  type    = string
  default = "cron(0 7 ? * MON *)"
}

# --- ai (was infra/ai.yml) --------------------------------------------------

variable "parser_image_uri" {
  type        = string
  description = "The backend image for the agenda parser, pinned by digest"
}

variable "parser_api" {
  type    = string
  default = "converse"

  validation {
    condition     = contains(["mantle", "converse"], var.parser_api)
    error_message = "parser_api must be mantle or converse."
  }
}

variable "parser_model" {
  type = string
}

variable "allowed_origins" {
  type        = list(string)
  description = "Origins the browser may call the parser from (CORS)"
}

variable "alert_email" {
  type        = string
  description = "Where the monthly budget alarm is sent"
}

variable "monthly_budget_usd" {
  type    = number
  default = 5
}
