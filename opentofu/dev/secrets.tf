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

# google_secret_manager_secret_version.gcp_sa_b64 removed: depended on
# google_service_account_key which is blocked by org policy.
# The secret shell (GCP_SA_B64) was already created and is managed with
# prevent_destroy. Populate the value manually via gcloud or GCP console.
