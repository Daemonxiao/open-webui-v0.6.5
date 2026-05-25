variable "region" {
  description = "Alibaba Cloud region for the application resources."
  type        = string
  default     = "cn-beijing"
}

variable "project_name" {
  description = "Short project name used in Alibaba Cloud resource names."
  type        = string
  default     = "open-webui"
}

variable "environment" {
  description = "Deployment environment name."
  type        = string
  default     = "hai"
}

variable "zone_id" {
  description = "Optional availability zone. Leave empty to select the first zone that supports VSwitch and the requested disk category."
  type        = string
  default     = ""
}

variable "vpc_cidr_block" {
  description = "VPC CIDR block."
  type        = string
  default     = "172.16.0.0/16"
}

variable "vswitch_cidr_block" {
  description = "VSwitch CIDR block."
  type        = string
  default     = "172.16.10.0/24"
}

variable "app_port" {
  description = "Public TCP port for Open WebUI."
  type        = number
  default     = 3000
}

variable "app_ingress_cidr_blocks" {
  description = "CIDR blocks allowed to reach the Open WebUI public port."
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "new_api_port" {
  description = "Public TCP port for the New API web UI and API."
  type        = number
  default     = 3001
}

variable "new_api_ingress_cidr_blocks" {
  description = "CIDR blocks allowed to reach the New API public port."
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "ssh_ingress_cidr_blocks" {
  description = "Optional CIDR blocks allowed to reach SSH. Empty keeps SSH closed."
  type        = list(string)
  default     = []
}

variable "image_id" {
  description = "Optional ECS image id. Leave empty to use the latest Aliyun Linux 3 x64 base image."
  type        = string
  default     = ""
}

variable "instance_type" {
  description = "Optional ECS instance type. Leave empty to select an available 2C4G type in the selected zone."
  type        = string
  default     = ""
}

variable "ecs_cpu_core_count" {
  description = "CPU cores used when instance_type is not set."
  type        = number
  default     = 2
}

variable "ecs_memory_size" {
  description = "Memory size in GiB used when instance_type is not set."
  type        = number
  default     = 4
}

variable "system_disk_category" {
  description = "System disk category."
  type        = string
  default     = "cloud_essd"
}

variable "system_disk_size" {
  description = "System disk size in GiB."
  type        = number
  default     = 40
}

variable "data_disk_category" {
  description = "Data disk category."
  type        = string
  default     = "cloud_essd"
}

variable "data_disk_performance_level" {
  description = "ESSD performance level for the data disk."
  type        = string
  default     = "PL0"
}

variable "data_disk_size" {
  description = "Data disk size in GiB for /opt/open-webui/data."
  type        = number
  default     = 80
}

variable "eip_bandwidth" {
  description = "EIP bandwidth in Mbps."
  type        = number
  default     = 5
}

variable "snapshot_repeat_weekdays" {
  description = "Automatic snapshot weekdays, where 1 is Monday and 7 is Sunday."
  type        = list(string)
  default     = ["1", "3", "5"]
}

variable "snapshot_time_points" {
  description = "Automatic snapshot hours in UTC+8."
  type        = list(string)
  default     = ["3"]
}

variable "snapshot_retention_days" {
  description = "Automatic snapshot retention days. -1 keeps snapshots permanently."
  type        = number
  default     = 14
}

variable "rds_engine_version" {
  description = "ApsaraDB RDS PostgreSQL engine version."
  type        = string
  default     = "13.0"
}

variable "rds_instance_type" {
  description = "Optional ApsaraDB RDS PostgreSQL instance class. Leave empty to select an available class in the selected zone."
  type        = string
  default     = ""
}

variable "rds_instance_storage" {
  description = "ApsaraDB RDS storage size in GiB."
  type        = number
  default     = 30
}

variable "rds_storage_type" {
  description = "ApsaraDB RDS storage type."
  type        = string
  default     = "cloud_essd"
}

variable "rds_category" {
  description = "ApsaraDB RDS instance category."
  type        = string
  default     = "Basic"
}

variable "rds_database_name" {
  description = "PostgreSQL database name for Open WebUI."
  type        = string
  default     = "openwebui"
}

variable "rds_account_name" {
  description = "PostgreSQL account name for Open WebUI."
  type        = string
  default     = "openwebui"
}

variable "new_api_database_name" {
  description = "PostgreSQL database name for New API."
  type        = string
  default     = "newapi"
}

variable "new_api_rds_account_name" {
  description = "PostgreSQL account name for New API."
  type        = string
  default     = "newapi"
}

variable "redis_url" {
  description = "Optional external Redis URL. Leave empty for this single-ECS deployment."
  type        = string
  default     = ""
  sensitive   = true
}

variable "websocket_manager" {
  description = "Optional Open WebUI websocket manager. Leave empty unless REDIS_URL is configured and horizontal scaling is required."
  type        = string
  default     = ""
}

variable "tags" {
  description = "Additional tags for supported resources."
  type        = map(string)
  default     = {}
}
