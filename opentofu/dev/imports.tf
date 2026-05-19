# Import blocks for resources already existing in GCP (created by prior partial applies).
# OpenTofu silently skips each import when the resource is already in state,
# so these blocks are safe to leave permanently.

locals {
  _bucket_id       = "${var.project_id}-${var.bucket_name}"
  _sa_viewer_email = "${var.service_account_id}@${var.project_id}.iam.gserviceaccount.com"
}

# ── Project APIs ──────────────────────────────────────────────────────────────
import {
  to = google_project_service.sqladmin[0]
  id = "${var.project_id}/sqladmin.googleapis.com"
}

import {
  to = google_project_service.secretmanager[0]
  id = "${var.project_id}/secretmanager.googleapis.com"
}

# Uncomment once container.googleapis.com has been enabled in GCP:
# import {
#   to = google_project_service.container[0]
#   id = "${var.project_id}/container.googleapis.com"
# }

# ── Storage bucket ────────────────────────────────────────────────────────────
import {
  to = google_storage_bucket.dataset[0]
  id = local._bucket_id
}

# ── Service accounts ──────────────────────────────────────────────────────────
import {
  to = google_service_account.dataset_viewer[0]
  id = "projects/${var.project_id}/serviceAccounts/${local._sa_viewer_email}"
}

# ── Bucket IAM ────────────────────────────────────────────────────────────────
import {
  to = google_storage_bucket_iam_member.viewer[0]
  id = "${local._bucket_id} roles/storage.objectViewer serviceAccount:${local._sa_viewer_email}"
}

import {
  to = google_storage_bucket_iam_member.uploader[0]
  id = "${local._bucket_id} roles/storage.objectAdmin serviceAccount:${local._sa_viewer_email}"
}

# ── Secret Manager ────────────────────────────────────────────────────────────
import {
  to = google_secret_manager_secret.gcp_sa_b64[0]
  id = "projects/${var.project_id}/secrets/GCP_SA_B64"
}

# ── Cloud SQL ─────────────────────────────────────────────────────────────────
import {
  to = google_sql_database_instance.postgres[0]
  id = "projects/${var.project_id}/instances/${var.db_instance_name}"
}
