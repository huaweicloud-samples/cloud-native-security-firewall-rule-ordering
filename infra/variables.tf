variable "hw_region" {
  type        = string
  description = "Huawei Cloud region to deploy into (e.g. ap-southeast-1). Check CFW availability in the target region before deployment."
  default     = "ap-southeast-1"
}

variable "identifier" {
  type        = string
  description = "Project identifier, used as a name suffix for all resources."
  default     = "cfw-strict-rule"
}

variable "cidr_block" {
  type        = string
  description = "VPC CIDR block."
  default     = "10.0.0.0/24"
}

# Huawei Cloud CFW is centralized: the "inspection" and "vpc_endpoints" tiers are dropped.
# No public NAT gateway is used (per deployment constraint); the workload ECS gets its own
# EIP, which is the egress path protected by CFW.
variable "subnet_cidr_blocks" {
  type        = map(list(string))
  description = "Subnet CIDR blocks per tier (keys are tier names)."
  default = {
    workload = ["10.0.0.0/28", "10.0.0.16/28", "10.0.0.32/28"]
  }
}

variable "number_azs" {
  type        = number
  description = "Number of Availability Zones to spread resources across (1-3)."
  default     = 1
  validation {
    condition     = var.number_azs > 0 && var.number_azs < 4
    error_message = "number_azs must be between 1 and 3."
  }
}

variable "instance_type" {
  type        = string
  description = "ECS flavor name (must exist in the target region/AZ)."
  default     = "s6.large.2"
}

variable "image_name_regex" {
  type        = string
  description = "Regex to select a public image for the ECS (x86_64). In ap-southeast-1 the public image is named 'Huawei Cloud EulerOS 2.0 Standard 64 bit'; the ARM variant is excluded by anchoring."
  default     = "^Huawei Cloud EulerOS 2\\.0 Standard 64 bit$"
}
