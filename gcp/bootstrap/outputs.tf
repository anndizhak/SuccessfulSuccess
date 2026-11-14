# The three values the successfulsuccess-gcp workspace needs as environment
# variables (TFC_GCP_*). None of them is a secret.

output "terraform_service_account_email" {
  value = google_service_account.terraform.email
}

output "api_service_account_email" {
  value = google_service_account.api.email
}

output "workload_provider_name" {
  description = "TFC_GCP_WORKLOAD_PROVIDER_NAME"
  value       = google_iam_workload_identity_pool_provider.hcp.name
}

output "project_number" {
  value = local.project_number
}
