resource "google_storage_bucket" "dataset" {
  count                       = var.enable_bucket ? 1 : 0
  name                        = "${var.project_id}-${var.bucket_name}"
  project                     = var.project_id
  location                    = var.location
  storage_class               = var.storage_class
  uniform_bucket_level_access = true
  force_destroy               = var.force_destroy

  labels = var.labels
}

resource "google_service_account" "dataset_viewer" {
  count        = var.enable_bucket ? 1 : 0
  account_id   = var.service_account_id
  display_name = var.service_account_display_name
  project      = var.project_id
}

resource "google_storage_bucket_iam_member" "viewer" {
  count  = var.enable_bucket ? 1 : 0
  bucket = google_storage_bucket.dataset[0].name
  role   = "roles/storage.objectViewer"
  member = "serviceAccount:${google_service_account.dataset_viewer[0].email}"
}

resource "google_storage_bucket_iam_member" "uploader" {
  count  = var.enable_bucket ? 1 : 0
  bucket = google_storage_bucket.dataset[0].name
  role   = "roles/storage.objectAdmin"
  member = "serviceAccount:${google_service_account.dataset_viewer[0].email}"
}

locals {
  dataset_object_name = var.dataset_object_name != "" ? var.dataset_object_name : (
    var.dataset_path != "" ? basename(var.dataset_path) : "dataset.tar.gz"
  )
}

resource "google_storage_bucket_object" "dataset" {
  count        = (var.enable_bucket && var.dataset_path != "") ? 1 : 0
  name         = local.dataset_object_name
  bucket       = google_storage_bucket.dataset[0].name
  source       = var.dataset_path
  content_type = var.dataset_content_type
}

resource "google_service_account_key" "dataset_viewer" {
  count              = var.enable_bucket ? 1 : 0
  service_account_id = google_service_account.dataset_viewer[0].name

  keepers = {
    rotate_on = var.key_rotation_id
  }
}

resource "google_secret_manager_secret" "sa_key" {
  count     = (var.enable_bucket && var.store_key_in_secret) ? 1 : 0
  project   = var.project_id
  secret_id = var.secret_id

  labels = var.labels

  replication {
    auto {}
  }
}

resource "google_secret_manager_secret_version" "sa_key" {
  count       = (var.enable_bucket && var.store_key_in_secret) ? 1 : 0
  secret      = google_secret_manager_secret.sa_key[0].id
  secret_data = google_service_account_key.dataset_viewer[0].private_key
}
