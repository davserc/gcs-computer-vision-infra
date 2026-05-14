resource "random_password" "grafana_admin" {
  length           = 20
  special          = true
  override_special = "!#%&*-_=+?"
}

resource "google_secret_manager_secret" "grafana_admin_password" {
  secret_id = "grafana-admin-password"
  project   = var.project_id

  replication {
    auto {}
  }

  depends_on = [google_project_service.secretmanager]
}

resource "google_secret_manager_secret_version" "grafana_admin_password" {
  secret      = google_secret_manager_secret.grafana_admin_password.id
  secret_data = random_password.grafana_admin.result
}
