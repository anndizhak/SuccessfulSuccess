# One-time bootstrap for the Google Cloud project, run from a laptop with the
# owner's own credentials (gcloud auth application-default login).
#
# It creates who may deploy, not what is deployed:
#   - the APIs that identity and federation need,
#   - a service account for Terraform and a separate one the API runs as,
#   - Workload Identity Federation, so HCP Terraform runs in the
#     successfulsuccess-gcp workspace get short-lived tokens of the Terraform
#     service account. No service account key exists anywhere.
#
# The state stays local (terraform.tfstate, git-ignored): the HCP workspace
# cannot manage the identity it logs in with. Everything else lives in ../ with
# its state in HCP Terraform.

terraform {
  required_version = ">= 1.10"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 7.0"
    }
    google-beta = {
      source  = "hashicorp/google-beta"
      version = "~> 7.0"
    }
  }
}

provider "google" {
  project = var.project_id
  region  = var.region
}

provider "google-beta" {
  project = var.project_id
  region  = var.region

  # The Firebase Management API rejects user credentials without a quota
  # project; this bills the API calls to the lab project itself.
  user_project_override = true
  billing_project       = var.project_id
}

data "google_project" "this" {}

locals {
  project_number = data.google_project.this.number
}

# --- APIs ---------------------------------------------------------------------

resource "google_project_service" "bootstrap" {
  for_each = toset([
    "cloudresourcemanager.googleapis.com",
    "serviceusage.googleapis.com",
    "iam.googleapis.com",
    "iamcredentials.googleapis.com",
    "sts.googleapis.com",
    "firebase.googleapis.com",
  ])

  service            = each.value
  disable_on_destroy = false
}

# --- Service accounts -----------------------------------------------------------

resource "google_service_account" "terraform" {
  account_id   = "terraform"
  display_name = "Terraform (HCP Terraform workspace successfulsuccess-gcp)"
  description  = "Deploys gcp/. Used only through Workload Identity Federation; it has no keys."

  depends_on = [google_project_service.bootstrap]
}

resource "google_service_account" "api" {
  account_id   = "meetings-api"
  display_name = "SuccessfulSuccess API (Cloud Run)"
  description  = "The identity the API container runs as. Not the default compute service account."

  depends_on = [google_project_service.bootstrap]
}

# What Terraform needs to deploy gcp/, and nothing broader: no Owner, no Editor,
# no right to change project IAM.
resource "google_project_iam_member" "terraform" {
  for_each = toset([
    "roles/run.admin",
    "roles/cloudsql.admin",
    "roles/artifactregistry.admin",
    "roles/secretmanager.admin",
    "roles/serviceusage.serviceUsageAdmin",
  ])

  project = var.project_id
  role    = each.value
  member  = google_service_account.terraform.member
}

# Service Account User only on the API's account, not on the whole project:
# Terraform may deploy Cloud Run as `api`, and as no other account.
resource "google_service_account_iam_member" "terraform_acts_as_api" {
  service_account_id = google_service_account.api.name
  role               = "roles/iam.serviceAccountUser"
  member             = google_service_account.terraform.member
}

# The API's project-level role. Terraform cannot grant project roles, so the
# bootstrap does. Access to the database password is granted on that one secret
# in ../ instead.
resource "google_project_iam_member" "api_cloudsql_client" {
  project = var.project_id
  role    = "roles/cloudsql.client"
  member  = google_service_account.api.member
}

# --- Firebase -----------------------------------------------------------------
# Adds Firebase to the project once (the Hosting site itself is in ../).
resource "google_firebase_project" "this" {
  provider = google-beta
  project  = var.project_id

  depends_on = [google_project_service.bootstrap]
}

# --- Workload Identity Federation for HCP Terraform ---------------------------------

resource "google_iam_workload_identity_pool" "hcp" {
  workload_identity_pool_id = "hcp-terraform"
  display_name              = "HCP Terraform"
  description               = "Runs of the ooad-anndizhak/successfulsuccess-gcp workspace"

  depends_on = [google_project_service.bootstrap]
}

resource "google_iam_workload_identity_pool_provider" "hcp" {
  workload_identity_pool_id          = google_iam_workload_identity_pool.hcp.workload_identity_pool_id
  workload_identity_pool_provider_id = "app-terraform-io"
  display_name                       = "app.terraform.io"

  oidc {
    issuer_uri = "https://app.terraform.io"
  }

  attribute_mapping = {
    "google.subject"                      = "assertion.sub"
    "attribute.terraform_organization_id" = "assertion.terraform_organization_id"
    "attribute.terraform_workspace_id"    = "assertion.terraform_workspace_id"
    "attribute.terraform_run_phase"       = "assertion.terraform_run_phase"
  }

  # The immutable IDs, not the names: an organization or workspace name can be
  # deleted and registered again by someone else; org-… and ws-… cannot.
  attribute_condition = join(" && ", [
    "assertion.terraform_organization_id == \"${var.hcp_organization_id}\"",
    "assertion.terraform_workspace_id == \"${var.hcp_workspace_id}\"",
  ])
}

resource "google_service_account_iam_member" "hcp_impersonates_terraform" {
  service_account_id = google_service_account.terraform.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "principalSet://iam.googleapis.com/${google_iam_workload_identity_pool.hcp.name}/attribute.terraform_workspace_id/${var.hcp_workspace_id}"
}
