# ---------------------------------------------------------------------------
# Logging: CFW logs (flow/access/attack) and VPC Flow Logs both land in LTS.
# (KMS disk encryption dropped: EVS requires an explicit KMS authorization
# grant that is not configured in this account, and disk encryption is not
# core to the CFW demo.)
# ---------------------------------------------------------------------------

# LTS group + streams for CFW logs.
resource "huaweicloud_lts_group" "cfw" {
  group_name  = "cfw-logs-${var.identifier}"
  ttl_in_days = 7
}

resource "huaweicloud_lts_stream" "cfw_flow" {
  group_id    = huaweicloud_lts_group.cfw.id
  stream_name = "cfw-flow"
  ttl_in_days = 7
}

resource "huaweicloud_lts_stream" "cfw_access" {
  group_id    = huaweicloud_lts_group.cfw.id
  stream_name = "cfw-access"
  ttl_in_days = 7
}

resource "huaweicloud_lts_stream" "cfw_attack" {
  group_id    = huaweicloud_lts_group.cfw.id
  stream_name = "cfw-attack"
  ttl_in_days = 7
}

# Route CFW logs to LTS (flow + access + attack log targets).
resource "huaweicloud_cfw_lts_log" "cfw" {
  fw_instance_id               = huaweicloud_cfw_firewall.cfw.id
  lts_log_group_id            = huaweicloud_lts_group.cfw.id
  lts_flow_log_stream_enable  = 1
  lts_flow_log_stream_id      = huaweicloud_lts_stream.cfw_flow.id
  lts_access_log_stream_enable = 1
  lts_access_log_stream_id    = huaweicloud_lts_stream.cfw_access.id
  lts_attack_log_stream_enable = 1
  lts_attack_log_stream_id    = huaweicloud_lts_stream.cfw_attack.id
}

# VPC Flow Logs -> LTS.
resource "huaweicloud_lts_group" "vpc_fl" {
  group_name  = "vpc-flowlog-${var.identifier}"
  ttl_in_days = 7
}

resource "huaweicloud_lts_stream" "vpc_fl" {
  group_id    = huaweicloud_lts_group.vpc_fl.id
  stream_name = "vpc-flow"
  ttl_in_days = 7
}

resource "huaweicloud_vpc_flow_log" "vpc" {
  name          = "vpc-flowlog-${var.identifier}"
  resource_type = "vpc"
  resource_id   = huaweicloud_vpc.vpc.id
  log_group_id  = huaweicloud_lts_group.vpc_fl.id
  log_stream_id = huaweicloud_lts_stream.vpc_fl.id
  traffic_type  = "all"
}
