output "instance_id" {
  description = "ECS instance id used by Cloud Assistant deployments."
  value       = alicloud_instance.app.id
}

output "instance_type" {
  description = "Resolved ECS instance type."
  value       = local.selected_instance_type
}

output "zone_id" {
  description = "Resolved availability zone."
  value       = local.selected_zone_id
}

output "eip_address" {
  description = "Public EIP address."
  value       = alicloud_eip_address.app.ip_address
}

output "app_url" {
  description = "Public Open WebUI URL for the current test deployment."
  value       = "http://${alicloud_eip_address.app.ip_address}:${var.app_port}"
}

output "health_url" {
  description = "Public health check URL."
  value       = "http://${alicloud_eip_address.app.ip_address}:${var.app_port}/health"
}

output "new_api_url" {
  description = "Public New API web UI URL."
  value       = "http://${alicloud_eip_address.app.ip_address}:${var.new_api_port}"
}

output "new_api_status_url" {
  description = "Public New API status endpoint URL."
  value       = "http://${alicloud_eip_address.app.ip_address}:${var.new_api_port}/api/status"
}

output "data_disk_id" {
  description = "Persistent Open WebUI data disk id."
  value       = alicloud_ecs_disk.data.id
}

output "security_group_id" {
  description = "Open WebUI security group id."
  value       = alicloud_security_group.app.id
}

output "rds_instance_id" {
  description = "ApsaraDB RDS PostgreSQL instance id."
  value       = alicloud_db_instance.postgres.id
}

output "rds_instance_type" {
  description = "Resolved ApsaraDB RDS PostgreSQL instance class."
  value       = local.selected_rds_type
}

output "database_url" {
  description = "PostgreSQL DATABASE_URL for Open WebUI."
  value       = "postgresql://${alicloud_db_account.app.account_name}:${random_password.rds.result}@${alicloud_db_instance.postgres.connection_string}:${alicloud_db_instance.postgres.port}/${var.rds_database_name}"
  sensitive   = true
}

output "new_api_database_url" {
  description = "PostgreSQL SQL_DSN for New API."
  value       = "postgresql://${alicloud_db_account.new_api.account_name}:${random_password.new_api_rds.result}@${alicloud_db_instance.postgres.connection_string}:${alicloud_db_instance.postgres.port}/${var.new_api_database_name}"
  sensitive   = true
}

output "redis_url" {
  description = "Optional Redis URL for Open WebUI. Empty for the default single-ECS deployment."
  value       = var.redis_url
  sensitive   = true
}

output "websocket_manager" {
  description = "Optional websocket manager for Open WebUI. Empty unless Redis is configured."
  value       = var.websocket_manager
}
