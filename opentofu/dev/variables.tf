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

variable "db_authorized_networks" {
  description = "Authorized networks for Cloud SQL public IP access."
  type = list(object({
    name  = string
    value = string
  }))
  default = []
}

variable "vm_name" {
  description = "Compute Engine VM name."
  type        = string
  default     = "cv-app-vm"
}

variable "enable_vm" {
  description = "Whether to create the Compute Engine VM."
  type        = bool
  default     = true
}

variable "vm_zone" {
  description = "Compute Engine zone."
  type        = string
  default     = "us-central1-a"
}

variable "vm_machine_type" {
  description = "Compute Engine machine type."
  type        = string
  default     = "e2-micro"
}

variable "vm_boot_image" {
  description = "Boot disk image."
  type        = string
  default     = "debian-cloud/debian-12"
}

variable "vm_boot_disk_size_gb" {
  description = "Boot disk size in GB."
  type        = number
  default     = 20
}

variable "vm_boot_disk_type" {
  description = "Boot disk type (e.g. pd-standard, pd-ssd)."
  type        = string
  default     = "pd-ssd"
}

variable "vm_network_tag" {
  description = "Network tag for firewall rules."
  type        = string
  default     = "cv-app"
}

variable "vm_service_account_id" {
  description = "VM service account ID (short name)."
  type        = string
  default     = "cv-app-vm"
}

variable "vm_service_account_display_name" {
  description = "VM service account display name."
  type        = string
  default     = "Computer Vision App VM"
}

variable "enable_observability" {
  description = "Whether to create a dedicated VM with Prometheus + Grafana."
  type        = bool
  default     = false
}

variable "obs_vm_name" {
  description = "Observability VM name."
  type        = string
  default     = "cv-obs-vm"
}

variable "obs_vm_zone" {
  description = "Observability VM zone."
  type        = string
  default     = "us-central1-a"
}

variable "obs_vm_machine_type" {
  description = "Observability VM machine type."
  type        = string
  default     = "e2-micro"
}

variable "obs_vm_boot_image" {
  description = "Observability VM boot image."
  type        = string
  default     = "debian-cloud/debian-12"
}

variable "obs_vm_boot_disk_size_gb" {
  description = "Observability VM boot disk size in GB."
  type        = number
  default     = 20
}

variable "obs_vm_boot_disk_type" {
  description = "Observability VM boot disk type."
  type        = string
  default     = "pd-ssd"
}

variable "obs_vm_network_tag" {
  description = "Network tag for observability firewall rules."
  type        = string
  default     = "cv-obs"
}

variable "obs_grafana_port" {
  description = "Grafana port exposed on the observability VM."
  type        = number
  default     = 3000
}

variable "obs_grafana_source_ranges" {
  description = "CIDR ranges allowed to access Grafana."
  type        = list(string)
  default     = ["186.22.17.19/32"]
}

variable "obs_grafana_admin_password" {
  description = "Grafana admin password."
  type        = string
  sensitive   = true
  default     = "admin"
}

variable "app_ports" {
  description = "TCP ports to expose on the VM."
  type        = list(number)
  default     = [80, 443]
}

variable "app_source_ranges" {
  description = "CIDR ranges allowed to reach the app ports."
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "compose_bucket_name" {
  description = "GCS bucket containing docker-compose.yml (optional)."
  type        = string
  default     = ""
}

variable "compose_source_path" {
  description = "Local path to docker-compose.yml to upload to GCS (optional)."
  type        = string
  default     = ""
}

variable "compose_object_name" {
  description = "GCS object name for docker-compose.yml."
  type        = string
  default     = "docker-compose.yml"
}

variable "app_bundle_source_path" {
  description = "Local path to a tar.gz of the app repo to upload (optional)."
  type        = string
  default     = ""
}

variable "app_bundle_object_name" {
  description = "GCS object name for the app bundle tar.gz."
  type        = string
  default     = "app_bundle.tar.gz"
}

variable "app_secret_names" {
  description = "Secret Manager secret names to export into the app env file."
  type        = list(string)
  default     = []
}

variable "app_secrets" {
  description = "Map of env var name -> secret value to create in Secret Manager."
  type        = map(string)
  sensitive   = true
  default     = {}
}

variable "app_env_file_name" {
  description = "Env file name created on the VM from Secret Manager (relative to app root)."
  type        = string
  default     = ".env.runtime"
}
