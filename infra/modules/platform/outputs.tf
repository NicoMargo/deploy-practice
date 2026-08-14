output "inventory_uri" {
  description = "Cloud Run URL for inventory"
  value       = module.inventory.uri
}

output "notifications_uri" {
  description = "Cloud Run URL for notifications"
  value       = module.notifications.uri
}

output "orders_uri" {
  description = "Cloud Run URL for orders (null until phase 2)"
  value       = length(module.orders) > 0 ? module.orders[0].uri : null
}

output "service_names" {
  description = "Resolved service names, used by the port-discovery step on floci"
  value = {
    inventory     = module.inventory.name
    notifications = module.notifications.name
    orders        = length(module.orders) > 0 ? module.orders[0].name : null
  }
}
