variable "project_id" {
  type    = string
  default = "spry-anndizhak-2026"
}

variable "region" {
  type    = string
  default = "us-central1"
}

variable "api_image" {
  description = <<-EOT
    The API image, pinned by digest. `make gcp-deploy` passes the one it just
    pushed. Until the first push it is Google's sample container, so the service
    can be created before the registry has an image in it.
  EOT
  type        = string
  default     = "us-docker.pkg.dev/cloudrun/container/hello"
}

variable "db_activation_policy" {
  description = <<-EOT
    ALWAYS runs the Cloud SQL instance; NEVER stops it. A stopped instance bills
    only its disk (~$1.70 a month for 10 GB). `make gcp-db-stop` / `gcp-db-start`.
  EOT
  type        = string
  default     = "ALWAYS"

  validation {
    condition     = contains(["ALWAYS", "NEVER"], var.db_activation_policy)
    error_message = "db_activation_policy must be ALWAYS or NEVER."
  }
}
