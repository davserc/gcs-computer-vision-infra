# Import blocks for resources already existing in GCP (created by prior partial applies).
# OpenTofu silently skips each import when the resource is already in state,
# so these blocks are safe to leave permanently.

locals {
  _bucket_id       = "${var.project_id}-${var.bucket_name}"
  _sa_viewer_email = "${var.service_account_id}@${var.project_id}.iam.gserviceaccount.com"
  _sa_vm_email     = "${var.vm_service_account_id}@${var.project_id}.iam.gserviceaccount.com"
}

# ── Project APIs ──────────────────────────────────────────────────────────────
import {
  to = google_project_service.compute[0]
  id = "${var.project_id}/compute.googleapis.com"
}

import {
  to = google_project_service.sqladmin[0]
  id = "${var.project_id}/sqladmin.googleapis.com"
}

import {
  to = google_project_service.secretmanager[0]
  id = "${var.project_id}/secretmanager.googleapis.com"
}

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

import {
  to = google_service_account.vm[0]
  id = "projects/${var.project_id}/serviceAccounts/${local._sa_vm_email}"
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

import {
  to = google_sql_database.app_db[0]
  id = "projects/${var.project_id}/instances/${var.db_instance_name}/databases/${var.db_name}"
}

import {
  to = google_sql_user.app_user[0]
  id = "${var.project_id}/${var.db_instance_name}/${var.db_user}"
}

# ── Project IAM ───────────────────────────────────────────────────────────────
import {
  to = google_project_iam_member.vm_secret_accessor[0]
  id = "${var.project_id} roles/secretmanager.secretAccessor serviceAccount:${local._sa_vm_email}"
}

import {
  to = google_project_iam_member.vm_cloudsql_client[0]
  id = "${var.project_id} roles/cloudsql.client serviceAccount:${local._sa_vm_email}"
}

# ── Compute ───────────────────────────────────────────────────────────────────
import {
  to = google_compute_firewall.app_ingress[0]
  id = "projects/${var.project_id}/global/firewalls/${var.vm_name}-ingress"
}

import {
  to = google_compute_instance.app_vm[0]
  id = "projects/${var.project_id}/zones/${var.vm_zone}/instances/${var.vm_name}"
}
