resource "google_project_service" "container" {
  count              = var.enable_gke ? 1 : 0
  project            = var.project_id
  service            = "container.googleapis.com"
  disable_on_destroy = false
}

resource "google_project_service" "sqladmin" {
  count              = var.enable_sql ? 1 : 0
  project            = var.project_id
  service            = "sqladmin.googleapis.com"
  disable_on_destroy = false
}

resource "google_project_service" "secretmanager" {
  count              = (var.enable_bucket || length(var.app_secrets) > 0 || (var.enable_bucket && var.store_key_in_secret)) ? 1 : 0
  project            = var.project_id
  service            = "secretmanager.googleapis.com"
  disable_on_destroy = false
}
