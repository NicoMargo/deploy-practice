locals {
  ports = {
    orders        = 8080
    inventory     = 8081
    notifications = 8082
  }

  # Every service needs to reach Secret Manager and know which project to read from.
  common_env = {
    GCP_PROJECT_ID               = var.project
    SECRET_MANAGER_EMULATOR_HOST = var.emulator_host
  }

  # orders is the only service with runtime dependencies on the other two.
  orders_ready = var.inventory_base_url != "" && var.notifications_base_url != ""
}

module "inventory" {
  source = "../cloud-run-service"

  project        = var.project
  location       = var.location
  name           = "${var.name_prefix}inventory"
  image          = var.inventory_image
  container_port = local.ports.inventory
  env_vars       = local.common_env
}

module "notifications" {
  source = "../cloud-run-service"

  project        = var.project
  location       = var.location
  name           = "${var.name_prefix}notifications"
  image          = var.notifications_image
  container_port = local.ports.notifications
  env_vars       = local.common_env
}

# Phase 2: only created once the upstream URLs are known. floci does not provide
# service-to-service DNS, so these are discovered from the host-published ports
# after inventory/notifications are up. On real GCP the module outputs' `uri`
# would be used directly and this two-phase split would not be needed.

module "orders" {
  source = "../cloud-run-service"
  count  = local.orders_ready ? 1 : 0

  project        = var.project
  location       = var.location
  name           = "${var.name_prefix}orders"
  image          = var.orders_image
  container_port = local.ports.orders

  env_vars = merge(local.common_env, {
    INVENTORY_BASE_URL     = var.inventory_base_url
    NOTIFICATIONS_BASE_URL = var.notifications_base_url
  })
}
