locals {
  compose_bucket_name      = trimspace(var.compose_bucket_name)
  compose_object_name      = trimspace(var.compose_object_name)
  compose_source_path      = trimspace(var.compose_source_path)
  app_bundle_source_path   = trimspace(var.app_bundle_source_path)
  app_bundle_object_name   = trimspace(var.app_bundle_object_name)
  app_secret_names         = length(var.app_secrets) > 0 ? join(" ", keys(var.app_secrets)) : join(" ", var.app_secret_names)
  app_secrets_nonsensitive = nonsensitive(var.app_secrets)
  effective_bundle_bucket = local.compose_bucket_name != "" ? local.compose_bucket_name : (
    (local.compose_source_path != "" || local.app_bundle_source_path != "") && var.enable_bucket ? google_storage_bucket.dataset[0].name : ""
  )
}
