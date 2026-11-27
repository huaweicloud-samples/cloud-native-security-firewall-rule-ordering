data "huaweicloud_images_image" "ecs" {
  name_regex  = var.image_name_regex
  visibility  = "public"
  most_recent = true
}

# Security group for the workload ECS (instance + management endpoints).
resource "huaweicloud_networking_secgroup" "instance" {
  name        = "sg-instance-${var.identifier}"
  description = "Security group for workload ECS"
}

resource "huaweicloud_networking_secgroup_rule" "ssh_mgmt" {
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 22
  port_range_max    = 22
  remote_ip_prefix  = "0.0.0.0/0"
  security_group_id = huaweicloud_networking_secgroup.instance.id
  description       = "SSH management via EIP"
}

resource "huaweicloud_networking_secgroup_rule" "vpc_all" {
  direction         = "ingress"
  ethertype         = "IPv4"
  remote_ip_prefix  = var.cidr_block
  security_group_id = huaweicloud_networking_secgroup.instance.id
  description       = "Intra-VPC all protocols/ports"
}

resource "huaweicloud_networking_secgroup_rule" "egress_icmp" {
  direction         = "egress"
  ethertype         = "IPv4"
  protocol          = "icmp"
  remote_ip_prefix  = "0.0.0.0/0"
  security_group_id = huaweicloud_networking_secgroup.instance.id
}

resource "huaweicloud_networking_secgroup_rule" "egress_http" {
  direction         = "egress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 80
  port_range_max    = 80
  remote_ip_prefix  = "0.0.0.0/0"
  security_group_id = huaweicloud_networking_secgroup.instance.id
}

resource "huaweicloud_networking_secgroup_rule" "egress_https" {
  direction         = "egress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 443
  port_range_max    = 443
  remote_ip_prefix  = "0.0.0.0/0"
  security_group_id = huaweicloud_networking_secgroup.instance.id
}

# Workload ECS. A management EIP (explicit resource, see vpc.tf) is bound for SSH
# login and provides the egress path that CFW protects. No public NAT is used.
resource "huaweicloud_compute_instance" "ecs" {
  count = var.number_azs

  name              = "instance-${count.index + 1}-${var.identifier}"
  flavor_name       = var.instance_type
  image_id          = data.huaweicloud_images_image.ecs.id
  security_group_ids = [huaweicloud_networking_secgroup.instance.id]
  availability_zone = element(data.huaweicloud_availability_zones.az.names, count.index)

  eip_id = huaweicloud_vpc_eip.ecs[count.index].id

  network {
    uuid = element(local.workload_subnet_ids, count.index)
  }

  system_disk_type       = "GPSSD"
  system_disk_size       = 40

  tags = {
    Purpose = "workload"
  }
}
