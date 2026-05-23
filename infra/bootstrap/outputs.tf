output "state_bucket" {
  description = "OSS bucket for Terraform remote state."
  value       = alicloud_oss_bucket.terraform_state.bucket
}

output "lock_instance_name" {
  description = "TableStore instance name for Terraform state locking."
  value       = alicloud_ots_instance.terraform_lock.name
}

output "lock_table_name" {
  description = "TableStore table name for Terraform state locking."
  value       = alicloud_ots_table.terraform_lock.table_name
}

output "lock_endpoint" {
  description = "TableStore endpoint for Terraform OSS backend locking."
  value       = "https://${alicloud_ots_instance.terraform_lock.name}.${var.region}.ots.aliyuncs.com"
}
