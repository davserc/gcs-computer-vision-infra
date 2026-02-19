resource "google_secret_manager_secret" "app" {
  for_each  = local.app_secrets_nonsensitive
  project   = var.project_id
  secret_id = each.key

  replication {
    auto {}
  }

  depends_on = [google_project_service.secretmanager]
}

resource "google_secret_manager_secret_version" "app" {
  for_each    = local.app_secrets_nonsensitive
  secret      = google_secret_manager_secret.app[each.key].id
  secret_data = each.value
}

resource "google_secret_manager_secret" "gcp_sa_b64" {
  count     = var.enable_bucket ? 1 : 0
  project   = var.project_id
  secret_id = "GCP_SA_B64"

  replication {
    auto {}
  }

  lifecycle {
    prevent_destroy = true
  }

  depends_on = [google_project_service.secretmanager]
}

resource "google_secret_manager_secret_version" "gcp_sa_b64" {
  count       = var.enable_bucket ? 1 : 0
  secret      = google_secret_manager_secret.gcp_sa_b64[0].id
  secret_data = google_service_account_key.dataset_viewer[0].private_key

  depends_on = [
    google_service_account_key.dataset_viewer,
  ]

  lifecycle {
    replace_triggered_by = [
      google_service_account_key.dataset_viewer[0].private_key,
    ]

    precondition {
      condition     = length(google_service_account_key.dataset_viewer[0].private_key) > 0
      error_message = "GCP_SA_B64 secret data is empty; service account key was not created."
    }
  }
}
