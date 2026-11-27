# ---------------------------------------------------------------------------
# Huawei Cloud CFW (云防火墙) — managed centralized firewall service.
# CFW is centralized: the firewall instance protects the workload ECS EIP(s),
# so all workload egress (which leaves via the ECS's own EIP) is inspected.
# No public NAT gateway is used; workload EIPs are protected directly by CFW.
# ---------------------------------------------------------------------------

# IMPORTANT: the CFW EIP-protection and ACL-rule APIs take "object_id" = the
# *protection object id* of the firewall (protect_objects where type=0, internet
# border), NOT the firewall instance id. Passing the firewall instance id is
# rejected by the backend with CFW.00200005 "operation content does not exist".
# The firewall instance id (local.cfw_internet_border_object_id) is only used by
# cfw_lts_log (fw_instance_id), which is a different API.
locals {
  cfw_internet_border_object_id = one([
    for po in huaweicloud_cfw_firewall.cfw.protect_objects : po.object_id if po.type == 0
  ])
}

resource "huaweicloud_cfw_firewall" "cfw" {
  name          = "cfw-${var.identifier}"
  charging_mode = "postPaid"
  flavor {
    # NOTE: the API normalizes the edition to its canonical string ("Professional").
    # Use the canonical value here, NOT "2",
    # otherwise every plan detects a diff (config "2" vs state "Professional") and
    # forces a firewall replacement (which then re-triggers the EIP-sync race below).
    version = "Professional"
  }
  tags = {
    Purpose = "strict-rule-ordering-demo"
  }
}

# Attach CFW to each ECS EIP so workload egress is inspected.
resource "huaweicloud_cfw_eip_protection" "ecs" {
  count = var.number_azs

  object_id = local.cfw_internet_border_object_id
  protected_eip {
    id          = huaweicloud_vpc_eip.ecs[count.index].id
    public_ipv4 = huaweicloud_vpc_eip.ecs[count.index].address
  }
}

# ---------------------------------------------------------------------------
# Access control rules.
#   type            = 0  (internet border firewall rule)
#   object_id       = firewall id (protected object)
#   action_type     = 0 allow / 1 deny
#   address_type    = 0 IP / 1 domain
#   direction       = 1 outbound (workload -> internet)
#   sequence        = explicit ordering (replicates Strict Rule Ordering)
#
# The `sequence` chain below implements the strict-rule-ordering policy:
#   stateless drop SSH/RDP  ->  allow ICMP  ->  allow .example.com (HTTP)
#   ->  allow .example.net (HTTPS)  ->  default-deny.
# In CFW a single allow rule both permits and logs; CFW records both allowed
# and denied traffic to LTS.
# ---------------------------------------------------------------------------
resource "huaweicloud_cfw_acl_rule" "deny_ssh" {
  object_id           = local.cfw_internet_border_object_id
  name                = "deny-ssh-${var.identifier}"
  type                = 0
  action_type         = 1
  address_type        = 0
  direction           = 1
  status              = 1
  long_connect_enable = 0
  source_addresses    = ["0.0.0.0/0"]
  destination_addresses = ["0.0.0.0/0"]
  custom_services {
    protocol    = 6
    source_port = "0-65535"
    dest_port   = "22"
  }
  sequence {
    top = 1
  }
}

resource "huaweicloud_cfw_acl_rule" "deny_rdp" {
  object_id           = local.cfw_internet_border_object_id
  name                = "deny-rdp-${var.identifier}"
  type                = 0
  action_type         = 1
  address_type        = 0
  direction           = 1
  status              = 1
  long_connect_enable = 0
  source_addresses    = ["0.0.0.0/0"]
  destination_addresses = ["0.0.0.0/0"]
  custom_services {
    protocol    = 6
    source_port = "0-65535"
    dest_port   = "3389"
  }
  sequence {
    dest_rule_id = huaweicloud_cfw_acl_rule.deny_ssh.id
  }
}

resource "huaweicloud_cfw_acl_rule" "allow_icmp" {
  object_id           = local.cfw_internet_border_object_id
  name                = "allow-icmp-${var.identifier}"
  type                = 0
  action_type         = 0
  address_type        = 0
  direction           = 1
  status              = 1
  long_connect_enable = 0
  source_addresses    = ["0.0.0.0/0"]
  destination_addresses = ["0.0.0.0/0"]
  custom_services {
    protocol    = 1
    source_port = "0-65535"
    dest_port   = "0-65535"
  }
  sequence {
    dest_rule_id = huaweicloud_cfw_acl_rule.deny_rdp.id
  }
}

resource "huaweicloud_cfw_acl_rule" "allow_example" {
  object_id              = local.cfw_internet_border_object_id
  name                   = "allow-example-com-${var.identifier}"
  type                   = 0
  action_type            = 0
  address_type           = 0
  destination_address_type = 1
  direction              = 1
  status                 = 1
  long_connect_enable    = 0
  source_addresses       = ["0.0.0.0/0"]
  destination_domain_address_name = "example.com"
  custom_services {
    protocol    = 6
    source_port = "0-65535"
    dest_port   = "80"
  }
  sequence {
    dest_rule_id = huaweicloud_cfw_acl_rule.allow_icmp.id
  }
}

resource "huaweicloud_cfw_acl_rule" "allow_example_net" {
  object_id              = local.cfw_internet_border_object_id
  name                   = "allow-example-net-${var.identifier}"
  type                   = 0
  action_type            = 0
  address_type           = 0
  destination_address_type = 1
  direction              = 1
  status                 = 1
  long_connect_enable    = 0
  source_addresses       = ["0.0.0.0/0"]
  destination_domain_address_name = "example.net"
  custom_services {
    protocol    = 6
    source_port = "0-65535"
    dest_port   = "443"
  }
  sequence {
    dest_rule_id = huaweicloud_cfw_acl_rule.allow_example.id
  }
}

# Default-deny for anything not explicitly allowed.
resource "huaweicloud_cfw_acl_rule" "deny_all" {
  object_id           = local.cfw_internet_border_object_id
  name                = "deny-all-${var.identifier}"
  type                = 0
  action_type         = 1
  address_type        = 0
  direction           = 1
  status              = 1
  long_connect_enable = 0
  source_addresses    = ["0.0.0.0/0"]
  destination_addresses = ["0.0.0.0/0"]
  sequence {
    bottom = 1
  }
}
