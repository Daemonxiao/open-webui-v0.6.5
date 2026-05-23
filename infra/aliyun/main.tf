locals {
  name_prefix = "${var.project_name}-${var.environment}"
  tags = merge(
    {
      Project     = var.project_name
      Environment = var.environment
      ManagedBy   = "terraform"
    },
    var.tags
  )
}

data "alicloud_zones" "available" {
  available_disk_category     = var.system_disk_category
  available_resource_creation = "VSwitch"
}

locals {
  selected_zone_id = var.zone_id != "" ? var.zone_id : data.alicloud_zones.available.zones[0].id
}

data "alicloud_instance_types" "selected" {
  count             = var.instance_type == "" ? 1 : 0
  availability_zone = local.selected_zone_id
  cpu_core_count    = var.ecs_cpu_core_count
  memory_size       = var.ecs_memory_size
  sorted_by         = "Price"
}

data "alicloud_images" "aliyun_linux" {
  count       = var.image_id == "" ? 1 : 0
  owners      = "system"
  name_regex  = "^aliyun_3_x64_20G_alibase.*"
  most_recent = true
}

data "alicloud_db_instance_classes" "postgres" {
  count                    = var.rds_instance_type == "" ? 1 : 0
  zone_id                  = local.selected_zone_id
  engine                   = "PostgreSQL"
  engine_version           = var.rds_engine_version
  category                 = var.rds_category
  db_instance_storage_type = var.rds_storage_type
  instance_charge_type     = "PostPaid"
}

locals {
  selected_instance_type = var.instance_type != "" ? var.instance_type : data.alicloud_instance_types.selected[0].instance_types[0].id
  selected_image_id      = var.image_id != "" ? var.image_id : data.alicloud_images.aliyun_linux[0].images[0].id
  selected_rds_type      = var.rds_instance_type != "" ? var.rds_instance_type : data.alicloud_db_instance_classes.postgres[0].instance_classes[0].instance_class
}

resource "alicloud_vpc" "app" {
  vpc_name   = "${local.name_prefix}-vpc"
  cidr_block = var.vpc_cidr_block

  tags = local.tags
}

resource "alicloud_vswitch" "app" {
  vswitch_name = "${local.name_prefix}-vsw"
  vpc_id       = alicloud_vpc.app.id
  zone_id      = local.selected_zone_id
  cidr_block   = var.vswitch_cidr_block

  tags = local.tags
}

resource "alicloud_security_group" "app" {
  security_group_name = "${local.name_prefix}-sg"
  description         = "Open WebUI ECS security group"
  vpc_id              = alicloud_vpc.app.id

  tags = local.tags
}

resource "alicloud_security_group_rule" "app_ingress" {
  for_each = toset(var.app_ingress_cidr_blocks)

  type              = "ingress"
  ip_protocol       = "tcp"
  nic_type          = "intranet"
  policy            = "accept"
  port_range        = "${var.app_port}/${var.app_port}"
  priority          = 1
  security_group_id = alicloud_security_group.app.id
  cidr_ip           = each.value
  description       = "Open WebUI public access"
}

resource "alicloud_security_group_rule" "ssh_ingress" {
  for_each = toset(var.ssh_ingress_cidr_blocks)

  type              = "ingress"
  ip_protocol       = "tcp"
  nic_type          = "intranet"
  policy            = "accept"
  port_range        = "22/22"
  priority          = 10
  security_group_id = alicloud_security_group.app.id
  cidr_ip           = each.value
  description       = "Optional break-glass SSH access"
}

resource "alicloud_security_group_rule" "egress_all" {
  type              = "egress"
  ip_protocol       = "all"
  nic_type          = "intranet"
  policy            = "accept"
  port_range        = "-1/-1"
  priority          = 1
  security_group_id = alicloud_security_group.app.id
  cidr_ip           = "0.0.0.0/0"
  description       = "Outbound access for image pulls and external APIs"
}

resource "alicloud_ram_role" "ecs" {
  role_name                   = "${local.name_prefix}-ecs-role"
  description                 = "RAM role attached to the Open WebUI ECS instance"
  force                       = true
  assume_role_policy_document = <<POLICY
{
  "Statement": [
    {
      "Action": "sts:AssumeRole",
      "Effect": "Allow",
      "Principal": {
        "Service": [
          "ecs.aliyuncs.com"
        ]
      }
    }
  ],
  "Version": "1"
}
POLICY
}

resource "alicloud_instance" "app" {
  instance_name              = local.name_prefix
  host_name                  = replace(local.name_prefix, "_", "-")
  image_id                   = local.selected_image_id
  instance_type              = local.selected_instance_type
  security_groups            = [alicloud_security_group.app.id]
  vswitch_id                 = alicloud_vswitch.app.id
  availability_zone          = local.selected_zone_id
  instance_charge_type       = "PostPaid"
  internet_charge_type       = "PayByTraffic"
  internet_max_bandwidth_out = 0
  system_disk_category       = var.system_disk_category
  system_disk_size           = var.system_disk_size
  user_data = base64encode(templatefile("${path.module}/cloud-init.sh.tftpl", {
    app_dir = "/opt/open-webui"
  }))

  tags = local.tags
}

resource "alicloud_ecs_ram_role_attachment" "app" {
  ram_role_name = alicloud_ram_role.ecs.role_name
  instance_id   = alicloud_instance.app.id
}

resource "alicloud_eip_address" "app" {
  address_name         = "${local.name_prefix}-eip"
  bandwidth            = var.eip_bandwidth
  internet_charge_type = "PayByTraffic"
  payment_type         = "PayAsYouGo"

  tags = local.tags
}

resource "alicloud_eip_association" "app" {
  allocation_id = alicloud_eip_address.app.id
  instance_id   = alicloud_instance.app.id
  instance_type = "EcsInstance"
}

resource "alicloud_ecs_disk" "data" {
  zone_id              = local.selected_zone_id
  disk_name            = "${local.name_prefix}-data"
  description          = "Open WebUI persistent data disk"
  category             = var.data_disk_category
  performance_level    = var.data_disk_category == "cloud_essd" ? var.data_disk_performance_level : null
  size                 = var.data_disk_size
  encrypted            = true
  enable_auto_snapshot = true
  delete_auto_snapshot = false

  tags = local.tags
}

resource "alicloud_ecs_disk_attachment" "data" {
  disk_id              = alicloud_ecs_disk.data.id
  instance_id          = alicloud_instance.app.id
  delete_with_instance = false
}

resource "alicloud_ecs_auto_snapshot_policy" "data" {
  auto_snapshot_policy_name = "${local.name_prefix}-data-snapshots"
  repeat_weekdays           = var.snapshot_repeat_weekdays
  time_points               = var.snapshot_time_points
  retention_days            = var.snapshot_retention_days
}

resource "alicloud_ecs_auto_snapshot_policy_attachment" "data" {
  auto_snapshot_policy_id = alicloud_ecs_auto_snapshot_policy.data.id
  disk_id                 = alicloud_ecs_disk.data.id
}

resource "random_password" "rds" {
  length           = 24
  special          = true
  override_special = "_"
}

resource "alicloud_rds_service_linked_role" "postgres" {
  service_name = "AliyunServiceRoleForRdsPgsqlOnEcs"
}

resource "alicloud_db_instance" "postgres" {
  engine                   = "PostgreSQL"
  engine_version           = var.rds_engine_version
  instance_type            = local.selected_rds_type
  instance_storage         = var.rds_instance_storage
  db_instance_storage_type = var.rds_storage_type
  instance_name            = "${local.name_prefix}-pg"
  category                 = var.rds_category
  instance_charge_type     = "Postpaid"
  vswitch_id               = alicloud_vswitch.app.id
  security_ips             = [var.vswitch_cidr_block]

  tags = local.tags

  depends_on = [alicloud_rds_service_linked_role.postgres]
}

resource "alicloud_db_database" "app" {
  instance_id    = alicloud_db_instance.postgres.id
  data_base_name = var.rds_database_name
  character_set  = "UTF8,C,en_US.utf8"
}

resource "alicloud_db_account" "app" {
  db_instance_id   = alicloud_db_instance.postgres.id
  account_name     = var.rds_account_name
  account_password = random_password.rds.result
  account_type     = "Normal"
}

resource "alicloud_db_account_privilege" "app" {
  instance_id  = alicloud_db_instance.postgres.id
  account_name = alicloud_db_account.app.account_name
  db_names     = [var.rds_database_name]
  privilege    = "DBOwner"
}
