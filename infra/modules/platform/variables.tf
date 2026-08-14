variable "project" {
  description = "GCP project id for this environment (isolation boundary)"
  type        = string
}

variable "location" {
  description = "Cloud Run region"
  type        = string
  default     = "us-central1"
}

variable "name_prefix" {
  description = <<-EOT
    Prefix for Cloud Run service names, e.g. "staging-".
    On real GCP the project boundary alone is enough and this can be empty;
    floci names its containers without the project, so a prefix keeps
    per-environment container/port discovery unambiguous.
  EOT
  type        = string
  default     = ""
}

# One variable per service rather than a single object, so a deploy can override
# just the services it rebuilt and let Terraform's variable precedence leave the
# rest on whatever terraform.tfvars pins. That is what makes the deploy
# differential without the pipeline having to know the previous image versions.
variable "inventory_image" {
  description = "Container image for inventory (prefer digest-pinned)"
  type        = string
}

variable "notifications_image" {
  description = "Container image for notifications (prefer digest-pinned)"
  type        = string
}

variable "orders_image" {
  description = "Container image for orders (prefer digest-pinned)"
  type        = string
}

variable "emulator_host" {
  description = "host:port where the container reaches Secret Manager (floci)"
  type        = string
}

variable "inventory_base_url" {
  description = "URL orders uses to reach inventory. Empty until discovered (phase 2)."
  type        = string
  default     = ""
}

variable "notifications_base_url" {
  description = "URL orders uses to reach notifications. Empty until discovered (phase 2)."
  type        = string
  default     = ""
}
