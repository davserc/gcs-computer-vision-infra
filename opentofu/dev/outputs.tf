output "bucket_name" {
  description = "Created bucket name."
  value       = var.enable_bucket ? google_storage_bucket.dataset[0].name : null
}

output "dataset_object_gs_uri" {
  description = "GCS URI for the uploaded dataset object (if provided)."
  value       = (var.enable_bucket && var.dataset_path != "") ? "gs://${google_storage_bucket.dataset[0].name}/${local.dataset_object_name}" : null
}

output "service_account_email" {
  description = "Service account email."
  value       = var.enable_bucket ? google_service_account.dataset_viewer[0].email : null
}


output "db_instance_connection_name" {
  description = "Cloud SQL instance connection name."
  value       = var.enable_sql ? google_sql_database_instance.postgres[0].connection_name : null
}

output "db_public_ip" {
  description = "Cloud SQL public IP."
  value       = var.enable_sql ? one([for ip in google_sql_database_instance.postgres[0].ip_address : ip.ip_address if ip.type == "PRIMARY"]) : null
}

output "db_name" {
  description = "Database name."
  value       = var.enable_sql ? google_sql_database.app_db[0].name : null
}

output "db_user" {
  description = "Database user."
  value       = var.enable_sql ? google_sql_user.app_user[0].name : null
}

output "vm_external_ip" {
  description = "VM external public IP."
  value       = var.enable_vm ? google_compute_instance.app_vm[0].network_interface[0].access_config[0].nat_ip : null
}

output "vm_name" {
  description = "VM name."
  value       = var.enable_vm ? google_compute_instance.app_vm[0].name : null
}

output "app_ports" {
  description = "Exposed app ports."
  value       = var.app_ports
}
