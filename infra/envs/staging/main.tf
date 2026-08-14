terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
  }
}

variable "project" {
  description = "GCP project id for this environment"
  type        = string
}

variable "name_prefix" {
  description = "Prefix applied to Cloud Run service names"
  type        = string
}

variable "inventory_image" {
  description = "Container image for inventory"
  type        = string
}

variable "notifications_image" {
  description = "Container image for notifications"
  type        = string
}

variable "orders_image" {
  description = "Container image for orders"
  type        = string
}

variable "floci_endpoint" {
  description = "floci-gcp base URL, as seen from where Terraform runs"
  type        = string
  default     = "http://localhost:4588"
}

variable "emulator_host" {
  description = "host:port where deployed containers reach floci"
  type        = string
  default     = "host.docker.internal:4588"
}

variable "inventory_base_url" {
  description = "Discovered in phase 1, injected into orders in phase 2"
  type        = string
  default     = ""
}

variable "notifications_base_url" {
  description = "Discovered in phase 1, injected into orders in phase 2"
  type        = string
  default     = ""
}

# floci is zero-auth: the token is never validated, but the provider refuses to
# initialise without some credential. On real GCP this block is replaced by
# Workload Identity Federation and the custom endpoints are dropped.
provider "google" {
  project      = var.project
  access_token = "dummy-token-for-floci"

  secret_manager_custom_endpoint = "${var.floci_endpoint}/v1/"
  cloud_run_v2_custom_endpoint   = "${var.floci_endpoint}/v2/"
}

module "platform" {
  source = "../../modules/platform"

  project       = var.project
  name_prefix   = var.name_prefix
  emulator_host = var.emulator_host

  inventory_image     = var.inventory_image
  notifications_image = var.notifications_image
  orders_image        = var.orders_image

  inventory_base_url     = var.inventory_base_url
  notifications_base_url = var.notifications_base_url
}

output "inventory_uri" {
  value = module.platform.inventory_uri
}

output "notifications_uri" {
  value = module.platform.notifications_uri
}

output "orders_uri" {
  value = module.platform.orders_uri
}

output "service_names" {
  value = module.platform.service_names
}
