locals {
  # Created by bootstrap/, which owns identities; this configuration only uses them.
  api_service_account = "meetings-api@${var.project_id}.iam.gserviceaccount.com"
  site_origins = [
    "https://${var.project_id}.web.app",
    "https://${var.project_id}.firebaseapp.com",
  ]
}

# --- APIs ---------------------------------------------------------------------
# Enabled here, so a fresh project is reproducible from code. Never disabled on
# destroy: switching an API off can break things outside this configuration.

resource "google_project_service" "this" {
  for_each = toset([
    "run.googleapis.com",
    "sqladmin.googleapis.com",
    "artifactregistry.googleapis.com",
    "secretmanager.googleapis.com",
    "firebasehosting.googleapis.com",
    "logging.googleapis.com",
  ])

  service            = each.value
  disable_on_destroy = false
}

# --- Artifact Registry (ECR) ----------------------------------------------------

resource "google_artifact_registry_repository" "api" {
  repository_id = "meetings"
  format        = "DOCKER"
  description   = "Backend images for Cloud Run"

  # 0.5 GB is free; an image is ~150 MB. Keep the last three versions.
  cleanup_policies {
    id     = "keep-last-3"
    action = "KEEP"
    most_recent_versions {
      keep_count = 3
    }
  }
  cleanup_policies {
    id     = "delete-older"
    action = "DELETE"
    condition {
      older_than = "86400s"
    }
  }

  depends_on = [google_project_service.this]
}

# --- Cloud SQL for PostgreSQL (Aurora Serverless v2) ---------------------------------

resource "google_sql_database_instance" "main" {
  name             = "meetings-pg"
  database_version = "POSTGRES_17"
  region           = var.region

  settings {
    # The smallest shared-core tier exists only in the Enterprise edition
    # (Postgres 16+ would default to Enterprise Plus).
    edition           = "ENTERPRISE"
    tier              = "db-f1-micro"
    availability_type = "ZONAL"
    activation_policy = var.db_activation_policy

    disk_type       = "PD_SSD"
    disk_size       = 10
    disk_autoresize = false

    # Unlike Aurora, Cloud SQL does not pause. Backups would add storage cost;
    # the data is the demo seed, reproducible from the migrations.
    backup_configuration {
      enabled = false
    }

    # A public IP with no authorized networks: nothing can connect directly.
    # Cloud Run reaches it through the Cloud SQL connector (IAM + TLS), which
    # needs no VPC, so no hourly connector or NAT.
    ip_configuration {
      ipv4_enabled = true
      ssl_mode     = "ENCRYPTED_ONLY"
    }

    deletion_protection_enabled = true

    user_labels = {
      project = "successfulsuccess"
      lab     = "lab9"
    }
  }

  # Kept until grading; flip both to false before `terraform destroy`.
  deletion_protection = true

  depends_on = [google_project_service.this]
}

resource "google_sql_database" "meetings" {
  name     = "meetings"
  instance = google_sql_database_instance.main.name
}

# Generated here, stored in the (encrypted) HCP state and in Secret Manager;
# never in the repository or on a command line.
resource "random_password" "db" {
  length  = 32
  special = false
}

resource "google_sql_user" "app" {
  name     = "app"
  instance = google_sql_database_instance.main.name
  password = random_password.db.result
}

# --- Secret Manager (SSM Parameter Store) ------------------------------------------
# The app reads one DATABASE_URL, so the secret is the whole URL with the
# password in it. It connects over the unix socket Cloud Run mounts at /cloudsql.

resource "google_secret_manager_secret" "database_url" {
  secret_id = "database-url"

  replication {
    auto {}
  }

  depends_on = [google_project_service.this]
}

resource "google_secret_manager_secret_version" "database_url" {
  secret = google_secret_manager_secret.database_url.id
  secret_data = format(
    "postgresql+asyncpg://%s:%s@/%s?host=/cloudsql/%s",
    google_sql_user.app.name,
    random_password.db.result,
    google_sql_database.meetings.name,
    google_sql_database_instance.main.connection_name,
  )
}

# Only the API's account may read it, and only this secret.
resource "google_secret_manager_secret_iam_member" "api_reads_database_url" {
  secret_id = google_secret_manager_secret.database_url.id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${local.api_service_account}"
}

# --- Cloud Run (Lambda + function URL) ----------------------------------------------

resource "google_cloud_run_v2_service" "api" {
  name     = "meetings-api"
  location = var.region
  # Firebase Hosting forwards /api/** over the public internet, so ingress
  # stays "all". Kept until grading, like the database.
  ingress             = "INGRESS_TRAFFIC_ALL"
  deletion_protection = true

  template {
    service_account = local.api_service_account

    scaling {
      min_instance_count = 0 # scale to zero: an idle month costs nothing
      max_instance_count = 2 # a ceiling on the bill and on database connections
    }

    max_instance_request_concurrency = 40

    volumes {
      name = "cloudsql"
      cloud_sql_instance {
        instances = [google_sql_database_instance.main.connection_name]
      }
    }

    containers {
      image = var.api_image

      resources {
        limits = {
          cpu    = "1"
          memory = "512Mi"
        }
        cpu_idle          = true # request-based billing: CPU only while serving
        startup_cpu_boost = true
      }

      env {
        name = "DATABASE_URL"
        value_source {
          secret_key_ref {
            secret  = google_secret_manager_secret.database_url.secret_id
            version = "latest"
          }
        }
      }
      env {
        name  = "CORS_ORIGINS"
        value = join(",", local.site_origins)
      }
      env {
        # Alembic runs in the entrypoint on each cold start (idempotent).
        name  = "RUN_MIGRATIONS_ON_START"
        value = "true"
      }
      env {
        # The same demo meetings for today as on AWS; inserted only when empty.
        name  = "SEED_DEMO_DATA"
        value = "true"
      }

      volume_mounts {
        name       = "cloudsql"
        mount_path = "/cloudsql"
      }
    }
  }

  depends_on = [
    google_project_service.this,
    google_secret_manager_secret_iam_member.api_reads_database_url,
    google_secret_manager_secret_version.database_url,
  ]
}

# Public, like the AWS function URL (AuthType NONE): the meetings API has no
# sign-in of its own yet, and Firebase Hosting can only rewrite to a public
# service. Sign-in (Cognito today, Identity Platform later) is the stretch goal.
resource "google_cloud_run_v2_service_iam_member" "public" {
  name     = google_cloud_run_v2_service.api.name
  location = google_cloud_run_v2_service.api.location
  role     = "roles/run.invoker"
  member   = "allUsers"
}
