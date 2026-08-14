resource "google_cloud_run_v2_service" "this" {
  project  = var.project
  name     = var.name
  location = var.location

  template {
    containers {
      image = var.image

      ports {
        container_port = var.container_port
      }

      dynamic "env" {
        for_each = var.env_vars
        content {
          name  = env.key
          value = env.value
        }
      }
    }
  }
}
