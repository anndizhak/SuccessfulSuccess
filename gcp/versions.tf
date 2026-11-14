# The core of SuccessfulSuccess on Google Cloud (Lab 9): Cloud SQL, Artifact
# Registry, the API on Cloud Run, the database password in Secret Manager.
# The frontend goes to Firebase Hosting with the Firebase CLI (hosting/).
#
# A separate root module with its own state, apart from infra/ (AWS): one plan
# cannot touch both clouds. Runs execute in HCP Terraform and log in to Google
# Cloud as terraform@… through Workload Identity Federation (TFC_GCP_* variables
# on the workspace, set up by bootstrap/). No key is stored anywhere.

terraform {
  required_version = ">= 1.10"

  cloud {
    organization = "ooad-anndizhak"

    workspaces {
      name = "successfulsuccess-gcp"
    }
  }

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 7.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }
}

provider "google" {
  project = var.project_id
  region  = var.region

  default_labels = {
    project = "successfulsuccess"
    lab     = "lab9"
  }
}
