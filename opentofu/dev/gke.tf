resource "google_service_account" "gke_nodes" {
  count        = var.enable_gke ? 1 : 0
  account_id   = "cv-gke-nodes"
  display_name = "Computer Vision GKE Node Pool"
  project      = var.project_id
}

resource "google_project_iam_member" "gke_nodes_logging" {
  count   = var.enable_gke ? 1 : 0
  project = var.project_id
  role    = "roles/logging.logWriter"
  member  = "serviceAccount:${google_service_account.gke_nodes[0].email}"
}

resource "google_project_iam_member" "gke_nodes_monitoring_writer" {
  count   = var.enable_gke ? 1 : 0
  project = var.project_id
  role    = "roles/monitoring.metricWriter"
  member  = "serviceAccount:${google_service_account.gke_nodes[0].email}"
}

resource "google_project_iam_member" "gke_nodes_monitoring_viewer" {
  count   = var.enable_gke ? 1 : 0
  project = var.project_id
  role    = "roles/monitoring.viewer"
  member  = "serviceAccount:${google_service_account.gke_nodes[0].email}"
}

resource "google_project_iam_member" "gke_nodes_registry_reader" {
  count   = var.enable_gke ? 1 : 0
  project = var.project_id
  role    = "roles/storage.objectViewer"
  member  = "serviceAccount:${google_service_account.gke_nodes[0].email}"
}

resource "google_container_cluster" "cv_platform" {
  count    = var.enable_gke ? 1 : 0
  name     = var.gke_cluster_name
  project  = var.project_id
  location = var.gke_zone

  remove_default_node_pool = true
  initial_node_count       = 1

  networking_mode = "VPC_NATIVE"
  ip_allocation_policy {}

  workload_identity_config {
    workload_pool = "${var.project_id}.svc.id.goog"
  }

  depends_on = [google_project_service.container]
}

resource "google_container_node_pool" "cv_platform_nodes" {
  count    = var.enable_gke ? 1 : 0
  name     = "cv-platform-pool"
  project  = var.project_id
  location = var.gke_zone
  cluster  = google_container_cluster.cv_platform[0].name

  autoscaling {
    min_node_count = var.gke_min_nodes
    max_node_count = var.gke_max_nodes
  }

  node_config {
    machine_type    = var.gke_machine_type
    disk_size_gb    = 50
    disk_type       = "pd-standard"
    service_account = google_service_account.gke_nodes[0].email

    oauth_scopes = [
      "https://www.googleapis.com/auth/cloud-platform",
    ]

    workload_metadata_config {
      mode = "GKE_METADATA"
    }
  }

  management {
    auto_repair  = true
    auto_upgrade = true
  }
}

# ── Cloud SQL Auth Proxy — Workload Identity ────────────────────────────────

resource "google_service_account" "cloudsql_proxy" {
  count        = var.enable_gke && var.enable_sql ? 1 : 0
  account_id   = "cv-cloudsql-proxy"
  display_name = "Cloud SQL Auth Proxy (GKE Workload Identity)"
  project      = var.project_id
}

resource "google_project_iam_member" "cloudsql_proxy_client" {
  count   = var.enable_gke && var.enable_sql ? 1 : 0
  project = var.project_id
  role    = "roles/cloudsql.client"
  member  = "serviceAccount:${google_service_account.cloudsql_proxy[0].email}"
}

# Permite que la KSA cv-platform/cv-platform-sa actúe como esta GSA
resource "google_service_account_iam_member" "workload_identity_binding" {
  count              = var.enable_gke && var.enable_sql ? 1 : 0
  service_account_id = google_service_account.cloudsql_proxy[0].name
  role               = "roles/iam.workloadIdentityUser"
  member             = "serviceAccount:${var.project_id}.svc.id.goog[cv-platform/cv-platform-sa]"
}
