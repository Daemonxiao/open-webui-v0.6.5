resource "alicloud_oss_bucket" "terraform_state" {
  bucket        = var.state_bucket_name
  storage_class = "Standard"
  force_destroy = false

  tags = var.tags
}

resource "alicloud_oss_bucket_acl" "terraform_state" {
  bucket = alicloud_oss_bucket.terraform_state.bucket
  acl    = "private"
}

resource "alicloud_ots_instance" "terraform_lock" {
  name             = var.lock_instance_name
  description      = "Terraform remote state lock for Open WebUI"
  instance_type    = "Capacity"
  network_type_acl = ["INTERNET", "VPC"]

  tags = var.tags
}

resource "alicloud_ots_table" "terraform_lock" {
  instance_name = alicloud_ots_instance.terraform_lock.name
  table_name    = var.lock_table_name
  time_to_live  = -1
  max_version   = 1

  primary_key {
    name = "LockID"
    type = "String"
  }
}
