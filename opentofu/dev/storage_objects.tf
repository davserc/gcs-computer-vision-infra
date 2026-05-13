resource "google_storage_bucket_object" "compose" {
  count  = (var.enable_bucket && local.compose_source_path != "") ? 1 : 0
  name   = local.compose_object_name
  bucket = local.effective_bundle_bucket
  source = local.compose_source_path

  content_type = "text/yaml"
}

resource "google_storage_bucket_object" "app_bundle" {
  count  = (var.enable_bucket && local.app_bundle_source_path != "") ? 1 : 0
  name   = local.app_bundle_object_name
  bucket = local.effective_bundle_bucket
  source = local.app_bundle_source_path

  content_type = "application/gzip"
}

