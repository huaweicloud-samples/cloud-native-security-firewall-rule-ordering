# cloud-native-security-firewall-rule-ordering

[![License](https://img.shields.io/badge/License-MIT--No--Attribution-green.svg)](LICENSE)
[![Huawei Cloud](https://img.shields.io/badge/Huawei%20Cloud-Best%20Practice-blue.svg)](https://www.huaweicloud.com)
[![Terraform](https://img.shields.io/badge/terraform-validated-success.svg)](https://www.terraform.io)

## 1. Overview

### Introduction

This practice demonstrates **strict Cloud Firewall (CFW) rule ordering** on Huawei Cloud: the `sequence` chain of `acl_rule` implements "deny SSH/RDP first → allow ICMP → allow .example.com (HTTP) / .example.net (HTTPS) → deny by default", and records both **allowed and denied** traffic to LTS (allow and deny events are logged to the same destination). This practice is delivered purely as Terraform (IaC).

---

## 2. Table of Contents

- [1. Overview](#1-overview)
- [2. Table of Contents](#2-table-of-contents)
- [3. Architecture Diagram](#3-architecture-diagram)
- [4. Highlights](#4-highlights)
- [5. Cloud Services Used](#5-cloud-services-used)
- [6. Prerequisites](#6-prerequisites)
- [7. Quick Start](#7-quick-start)
- [8. Step-by-Step Deployment](#8-step-by-step-deployment)
- [9. Usage / Verification](#9-usage--verification)
- [10. Cleanup](#10-cleanup)
- [11. Detailed Explanation](#11-detailed-explanation)
- [12. Dependencies](#12-dependencies)
- [13. FAQ / Troubleshooting](#13-faq--troubleshooting)
- [14. Contributing](#14-contributing)
- [15. License](#15-license)
- [16. Contact / Maintainers](#16-contact--maintainers)

---

## 3. Architecture Diagram

```
┌──────────────────────────────────────────────┐
│ VPC (10.0.0.0/24)                            │
│                                              │
│  workload 子网 ──(0.0.0.0/0 默认路由)──▶ 互联网  │
│  (ECS + 管理 EIP)                            │
│        │                                     │
│        │ EIP 为 CFW 保护对象                   │
│        ▼                                     │
│  ┌────────────────────┐                      │
│  │ CFW 云防火墙        │                      │
│  │ (互联网边界, type=0) │                      │
│  │ acl_rule 严格排序   │                      │
│  │ → LTS 日志          │                      │
│  └────────────────────┘                      │
└──────────────────────────────────────────────┘
```

> Traffic path: the workload ECS is directly bound to an EIP for outbound access, and that EIP is managed by CFW as a protected object (Internet boundary). Therefore, outbound traffic from the ECS is inspected by CFW before it is allowed or denied. This practice **does not use a NAT gateway**.

See `docs/architecture.md` for details.

---

## 4. Highlights

- **Strict rule ordering**: `acl_rule.sequence` (top / dest_rule_id / bottom) is explicitly chained to produce the readable order "deny SSH/RDP → allow ICMP → allow specified domains → deny by default".
- **Dual logging to the same destination**: a single CFW allow rule records both allowed and denied traffic; the `cfw-access` / `cfw-flow` streams in LTS can correlate allow and deny events for the same destination, which simplifies traceability.
- **EIP direct egress + CFW protected object**: the workload ECS uses a management EIP for outbound access, and the EIP is added to the firewall through `cfw_eip_protection`; no NAT gateway is required and the deployment model is simple and clear.
- **Offline reproducibility**: `.terraformrc` plus dev_overrides provide a local provider cache, so `terraform init` / `validate` / `apply` can all be completed offline.

---

## 5. Cloud Services Used

| Cloud service | Role | Notes |
|---|---|---|
| VPC (Virtual Private Cloud) | Provides an isolated network environment | Single VPC, single subnet |
| ECS (Elastic Cloud Server) | Acts as the workload egress host | s6.large.2 |
| EIP (Elastic IP) | Provides ECS management and egress entry point | CFW protected object |
| CFW (Cloud Firewall) | Inspects and orders Internet boundary traffic | postPaid (pay-as-you-go) |
| LTS (Log Tank Service) | Receives CFW logs and VPC flow logs | cfw-logs / vpc-flowlog |

---

## 6. Prerequisites

- Terraform >= 1.3 (1.10 used for validation), `huaweicloud` provider v1.96.0
- A Huawei Cloud account (default region `cn-north-4`) with VPC / CFW / LTS / ECS permissions
- `HW_ACCESS_KEY` / `HW_SECRET_KEY` / `HW_REGION_NAME` environment variables (credentials are provided only through environment variables; do not write them into code or configuration files)
- The `huaweicloud` v1.96.0 provider cached locally

> Region note: the CFW pay-as-you-go (postPaid) mode is supported only in some regions (for example, ap-southeast-1). If the target region does not support pay-as-you-go, use subscription mode or change the region.

---

## 7. Quick Start

```bash
cd infra
export TF_CLI_CONFIG_FILE=.terraformrc
export HW_ACCESS_KEY=<your-access-key> HW_SECRET_KEY=<your-secret-key> HW_REGION_NAME=cn-north-4
terraform init
terraform validate
terraform plan
terraform apply
```

---

## 8. Step-by-Step Deployment

1. **Environment preparation**: install Terraform and the `huaweicloud` provider; set the environment variables `HW_ACCESS_KEY` / `HW_SECRET_KEY` / `HW_REGION_NAME`.
2. **Enter the infra directory**: `cd infra`, then set `TF_CLI_CONFIG_FILE=.terraformrc`.
3. **terraform init**: initialize the provider (using the local cache to avoid repeated downloads).
4. **terraform validate**: check syntax and provider version constraints.
5. **terraform plan**: confirm the resources to be created (VPC / subnet / EIP / ECS / CFW / LTS / 6 acl_rules).
6. **terraform apply**: execute after confirming the plan; a return code of 0 means the deployment succeeded.
7. **View resources**: in the console, open "Cloud Firewall > Access Control > Internet Boundary" and check the order of the 6 rules; in "Log Tank Service (LTS)", check the `cfw-logs-<id>` and `vpc-flowlog-<id>` log groups.

---

## 9. Usage / Verification

### Usage

1. In the console, open "Cloud Firewall > Access Control > Internet Boundary" and confirm that the 6 rules take effect in the intended order.
2. Generate outbound traffic from the workload subnet (an ECS without an EIP is recommended, or temporarily unbind the EIP):
- Access `example.com` (HTTP) / `example.net` (HTTPS) → allowed and logged;
- Access other domains/ports → denied by `deny-all`.
3. Under the `cfw-logs-<id>` log group in LTS, view `cfw-access` / `cfw-flow` and confirm that both allowed and denied events are recorded.
4. VPC Flow Logs land in the `vpc-flowlog-<id>` log group.

See `docs/architecture.md` and `docs/deployment-guide.md` for details.

After deployment, follow these steps to verify that the business functionality works before considering the delivery complete.

---

## 10. Cleanup

```bash
cd infra
terraform destroy
```

- Before destroying, confirm `HW_ACCESS_KEY` / `HW_SECRET_KEY` and the target region again.
- After CFW, EIP, LTS and other resources are deleted, check the console to make sure nothing remains (deleting a CFW instance may require unbinding protected objects first).
- Destruction is the final cleanup action and cannot be undone; export any intermediate data you need to keep in advance.

---

## 11. Detailed Explanation

- For the directory structure and the responsibility of each `.tf` file, see the "Directory Structure" section.
- For architecture details, acl_rule ordering, the CFW protected-object mechanism, and the two LTS log destinations: `docs/architecture.md`.
- For the deployment process, command list, and cleanup points: `docs/deployment-guide.md`.

---

## 12. Dependencies

- This practice is based on Huawei Cloud CFW / LTS / VPC / ECS / EIP services and follows the official Huawei Cloud product documentation.

---

## 13. FAQ / Troubleshooting

### FAQ

- **Q: Why not use a NAT gateway?**
  A: This practice emphasizes the simplest deployment model of "EIP direct egress + CFW protected object". If you need NAT egress, switch to `huaweicloud_nat_gateway` and add the NAT EIP to the CFW protected objects.
- **Q: Are there region restrictions for CFW pay-as-you-go mode?**
  A: The pay-as-you-go (postPaid) mode is supported only in some regions (such as `ap-southeast-1`); in other regions, use subscription mode or adjust the setting manually in the console.
- **Q: How do I change the rule order?**
  A: Edit the `huaweicloud_cfw_acl_rule.sequence` blocks in `infra/firewall.tf` (top / bottom / dest_rule_id), then run `terraform apply`.
- **Q: Denied events are not visible in the logs?**
  A: Confirm that `cfw_lts_log.cfw` has `lts_access_log_stream_enable` / `lts_flow_log_stream_enable` / `lts_attack_log_stream_enable` enabled; CFW records both allowed and denied traffic by default.

---

## 14. Contributing

- This repository puts "compliance + reproducibility" first; every PR must preserve the LICENSE and the numbered README structure.
- When modifying `.tf` files, do not change existing `resource` / `data` / `output` blocks; only add necessary explanatory text in header comments.

---

## 15. License

This practice is licensed under **MIT No Attribution**; see the `LICENSE` file in the repository root.

---

## 16. Contact / Maintainers
| Item | Content |
|---|---|
| **Creator** | [dgc-git](https://github.com/dgc-git) |
| **Maintainer** | [dgc-git](https://github.com/dgc-git) |
| **Contact** | GitHub Issues / PR (see [Section 14](#14-contributing)) |
