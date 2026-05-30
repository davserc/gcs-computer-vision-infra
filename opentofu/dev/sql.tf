resource "google_sql_database_instance" "postgres" {
  count               = var.enable_sql ? 1 : 0
  name                = var.db_instance_name
  project             = var.project_id
  region              = var.location
  database_version    = var.db_version
  deletion_protection = false

  settings {
    tier              = var.db_tier
    availability_type = "ZONAL"
    disk_size         = var.db_disk_size_gb
    disk_autoresize   = var.db_disk_autoresize

    ip_configuration {
      ipv4_enabled = true
      # Sin authorized_networks: Cloud SQL Auth Proxy autentica via IAM/mTLS.
      # Los pods se conectan a localhost:5432 (sidecar), nunca en TCP directo.
    }
  }

  depends_on = [
    google_project_service.sqladmin,
  ]
}

resource "google_sql_database" "app_db" {
  count    = var.enable_sql ? 1 : 0
  name     = var.db_name
  project  = var.project_id
  instance = google_sql_database_instance.postgres[0].name
}

resource "google_sql_user" "app_user" {
  count           = var.enable_sql ? 1 : 0
  name            = var.db_user
  project         = var.project_id
  instance        = google_sql_database_instance.postgres[0].name
  password        = var.db_password
  deletion_policy = "ABANDON"
}
