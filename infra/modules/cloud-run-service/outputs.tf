output "uri" {
  description = "URL Cloud Run assigned to this service"
  value       = google_cloud_run_v2_service.this.uri
}

output "name" {
  description = "Service name"
  value       = google_cloud_run_v2_service.this.name
}

output "id" {
  description = "Fully qualified service id"
  value       = google_cloud_run_v2_service.this.id
}
