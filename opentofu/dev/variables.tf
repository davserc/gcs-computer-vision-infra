variable "project_id" {
  description = "GCP project ID."
  type        = string
}

variable "bucket_name" {
  description = "Bucket name for the dataset."
  type        = string
  default     = "computer_vision_yolo"
}

variable "enable_bucket" {
  description = "Whether to create the dataset bucket and related objects/iam."
  type        = bool
  default     = true
}

variable "dataset_path" {
  description = "Local path to a compressed dataset file to upload (optional)."
  type        = string
  default     = ""
}

variable "dataset_object_name" {
  description = "Object name to use in GCS (defaults to basename of dataset_path)."
  type        = string
  default     = ""
}

variable "dataset_content_type" {
  description = "Content-Type for the uploaded dataset object."
  type        = string
  default     = "application/gzip"
}

variable "location" {
  description = "Bucket location, e.g. US, EU, or a region like us-central1."
  type        = string
  default     = "us-central1"
}

variable "storage_class" {
  description = "Bucket storage class."
  type        = string
  default     = "STANDARD"
}

variable "force_destroy" {
  description = "Whether to allow bucket deletion with objects inside."
  type        = bool
  default     = false
}

variable "labels" {
  description = "Labels to apply to resources."
  type        = map(string)
  default     = {}
}

variable "service_account_id" {
  description = "Service account ID (short name)."
  type        = string
  default     = "cv-dataset-viewer"
}

variable "service_account_display_name" {
  description = "Service account display name."
  type        = string
  default     = "Computer Vision Dataset Viewer"
}

variable "key_rotation_id" {
  description = "Change this value to force key rotation."
  type        = string
  default     = "initial"
}

variable "store_key_in_secret" {
  description = "Whether to store the key in Secret Manager."
  type        = bool
  default     = false
}

variable "secret_id" {
  description = "Secret Manager secret ID to store the key if enabled."
  type        = string
  default     = "cv-dataset-viewer-key"
}

variable "db_instance_name" {
  description = "Cloud SQL instance name."
  type        = string
  default     = "cv-postgres"
}

variable "enable_sql" {
  description = "Whether to create the Cloud SQL instance and database/user."
  type        = bool
  default     = true
}

variable "db_version" {
  description = "Cloud SQL database version."
  type        = string
  default     = "POSTGRES_15"
}

variable "db_tier" {
  description = "Cloud SQL machine tier."
  type        = string
  default     = "db-f1-micro"
}

variable "db_disk_size_gb" {
  description = "Cloud SQL disk size in GB."
  type        = number
  default     = 10
}

variable "db_disk_autoresize" {
  description = "Enable Cloud SQL disk autosize."
  type        = bool
  default     = true
}

variable "db_name" {
  description = "PostgreSQL database name."
  type        = string
  default     = "computer-vision"
}

variable "db_user" {
  description = "PostgreSQL user."
  type        = string
  default     = "sauron"
}

variable "db_password" {
  description = "PostgreSQL user password."
  type        = string
  sensitive   = true
}

variable "app_secrets" {
  description = "Map of env var name -> secret value to create in Secret Manager."
  type        = map(string)
  sensitive   = true
  default     = {}
}

# ── GKE ───────────────────────────────────────────────────────────────────────

variable "enable_gke" {
  description = "Whether to create the GKE cluster and node pool."
  type        = bool
  default     = true
}

variable "gke_cluster_name" {
  description = "GKE cluster name."
  type        = string
  default     = "cv-platform"
}

variable "gke_zone" {
  description = "GKE cluster zone."
  type        = string
  default     = "us-central1-a"
}

variable "gke_machine_type" {
  description = "GKE node machine type."
  type        = string
  default     = "e2-standard-2"
}

variable "gke_min_nodes" {
  description = "Minimum number of GKE nodes."
  type        = number
  default     = 1
}

variable "gke_max_nodes" {
  description = "Maximum number of GKE nodes."
  type        = number
  default     = 3
}
