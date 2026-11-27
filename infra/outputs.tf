output "vpc_id" {
  description = "VPC ID."
  value       = huaweicloud_vpc.vpc.id
}

output "cfw_firewall_id" {
  description = "CFW firewall instance ID."
  value       = huaweicloud_cfw_firewall.cfw.id
}

output "ecs_ids" {
  description = "Workload ECS instance IDs."
  value       = huaweicloud_compute_instance.ecs[*].id
}

output "ecs_management_ips" {
  description = "Public (EIP) IPs for SSH management of the workload ECS."
  value       = huaweicloud_compute_instance.ecs[*].access_ip_v4
}

output "ecs_eip_addresses" {
  description = "ECS EIP addresses protected by CFW (workload egress path)."
  value       = huaweicloud_vpc_eip.ecs[*].address
}
