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
  default     = "ow-hai-tf-lock"

  validation {
    condition     = can(regex("^[A-Za-z][A-Za-z0-9-]{1,14}[A-Za-z0-9]$", var.lock_instance_name))
    error_message = "The lock instance name must be 3-16 characters, start with a letter, end with a letter or digit, and contain only letters, digits, or hyphens."
  }
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
