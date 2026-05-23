variable "region" {
  description = "Alibaba Cloud region for the Terraform state backend resources."
  type        = string
  default     = "cn-beijing"
}

variable "state_bucket_name" {
  description = "Globally unique OSS bucket name used for Terraform remote state."
  type        = string
}

variable "lock_instance_name" {
  description = "TableStore instance name used by the Terraform OSS backend for state locking."
  type        = string
  default     = "open-webui-hai-tf-lock"
}

variable "lock_table_name" {
  description = "TableStore table name used by the Terraform OSS backend for state locking."
  type        = string
  default     = "terraform_locks"
}

variable "tags" {
  description = "Tags applied to bootstrap resources that support tagging."
  type        = map(string)
  default = {
    Project     = "open-webui"
    Environment = "hai"
    ManagedBy   = "terraform"
  }
}
