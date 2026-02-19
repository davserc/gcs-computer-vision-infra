resource "google_project_iam_member" "vm_secret_accessor" {
  count   = (var.enable_vm && (length(var.app_secret_names) > 0 || length(var.app_secrets) > 0 || var.enable_bucket)) ? 1 : 0
  project = var.project_id
  role    = "roles/secretmanager.secretAccessor"
  member  = "serviceAccount:${google_service_account.vm[0].email}"
}

resource "google_project_iam_member" "vm_cloudsql_client" {
  count   = var.enable_sql ? 1 : 0
  project = var.project_id
  role    = "roles/cloudsql.client"
  member  = "serviceAccount:${google_service_account.vm[0].email}"
}
