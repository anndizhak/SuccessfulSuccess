output "api_url" {
  description = "The Cloud Run URL (the site reaches it as /api/** on its own origin)."
  value       = google_cloud_run_v2_service.api.uri
}

output "site_url" {
  value = local.site_origins[0]
}

output "registry" {
  description = "Where `make gcp-push` pushes the API image."
  value       = "${var.region}-docker.pkg.dev/${var.project_id}/${google_artifact_registry_repository.api.repository_id}"
}

output "db_connection_name" {
  value = google_sql_database_instance.main.connection_name
}

output "db_state" {
  value = var.db_activation_policy == "ALWAYS" ? "running" : "stopped"
}
