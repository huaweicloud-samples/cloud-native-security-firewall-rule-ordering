data "huaweicloud_availability_zones" "az" {}

locals {
  # Build a flat map "tier-az" -> {tier, az_index, cidr} for subnet creation.
  # Iterates over whatever tiers exist in var.subnet_cidr_blocks.
  tier_subnets = merge(flatten([
    for tier, cidrs in var.subnet_cidr_blocks : [
      for i in range(var.number_azs) : {
        "${tier}-${i}" = {
          tier     = tier
          az_index = i
          cidr     = cidrs[i]
        }
      }
    ]
  ])...)
}

resource "huaweicloud_vpc" "vpc" {
  name = "vpc-${var.identifier}"
  cidr = var.cidr_block
}

resource "huaweicloud_vpc_subnet" "subnets" {
  for_each = local.tier_subnets

  name       = "subnet-${each.value.tier}-${each.value.az_index}-${var.identifier}"
  cidr       = each.value.cidr
  gateway_ip = cidrhost(each.value.cidr, 1)
  vpc_id     = huaweicloud_vpc.vpc.id
  availability_zone = element(data.huaweicloud_availability_zones.az.names, each.value.az_index)

  tags = {
    Tier = each.value.tier
  }
}

locals {
  workload_subnet_ids = [for s in huaweicloud_vpc_subnet.subnets : s.id if s.tags.Tier == "workload"]
}

# Workload ECS EIP(s). This is the egress path that CFW protects.
# NOTE: No public NAT gateway is used (per deployment constraint).
resource "huaweicloud_vpc_eip" "ecs" {
  count = var.number_azs

  publicip {
    type = "5_bgp"
  }
  bandwidth {
    share_type  = "PER"
    size        = 5
    name        = "eip-ecs-${count.index}-${var.identifier}"
    charge_mode = "traffic"
  }
  tags = {
    Purpose = "ecs-egress"
  }
}
