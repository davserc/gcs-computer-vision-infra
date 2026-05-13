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
      # Allow connections from anywhere — K8s nodes connect via public IP.
      # Restrict to GKE node CIDR in production.
      authorized_networks {
        name  = "allow-all"
        value = "0.0.0.0/0"
      }
      dynamic "authorized_networks" {
        for_each = var.db_authorized_networks
        content {
          name  = authorized_networks.value.name
          value = authorized_networks.value.value
        }
      }
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
