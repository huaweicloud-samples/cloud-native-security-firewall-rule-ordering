# cloud-native-security-firewall-rule-ordering · 云防火墙严格规则排序（日志示例）

[![License](https://img.shields.io/badge/License-MIT--No--Attribution-green.svg)](LICENSE)
[![Huawei Cloud](https://img.shields.io/badge/Huawei%20Cloud-Best%20Practice-blue.svg)](https://www.huaweicloud.com)
[![Terraform](https://img.shields.io/badge/terraform-validated-success.svg)](https://www.terraform.io)

## 1. 简介 / Overview

### 简介


在华为云上演示 **云防火墙（CFW）严格规则排序**：用 `acl_rule` 的 `sequence` 链实现「先拒绝 SSH/RDP →
放行 ICMP → 放行 .example.com(HTTP) / .example.net(HTTPS) → 默认拒绝」，并把**放行与拒绝**流量
同时记录到 LTS（放行/拒绝同目标日志）。本实践为纯 Terraform（IaC）交付。

---

## 2. 目录

- [1. 简介 / Overview](#1-简介--overview)
- [2. 目录](#2-目录)
- [3. 架构图](#3-架构图)
- [4. 方案亮点](#4-方案亮点)
- [5. 涉及云服务](#5-涉及云服务)
- [6. 前置条件](#6-前置条件)
- [7. 快速开始](#7-快速开始)
- [8. 分步部署](#8-分步部署)
- [9. 使用方法 / 验证](#9-使用方法--验证)
- [10. 清理资源](#10-清理资源)
- [11. 详细说明](#11-详细说明)
- [12. 依赖](#12-依赖)
- [13. FAQ / 故障排除](#13-faq--故障排除)
- [14. 贡献指南](#14-贡献指南)
- [15. 许可证](#15-许可证)
- [16. 联系方式 / 维护者](#16-联系方式--维护者)

---

## 3. 架构图

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

> 流量路径说明：workload ECS 直接绑定 EIP 出网，该 EIP 被 CFW 纳管为保护对象（互联网边界），
> 因此 ECS 的外访流量经 CFW 检查后放行或拒绝。本实践**不使用 NAT 网关**。

详见 `docs/architecture.md`。

---

## 4. 方案亮点

- **严格规则排序**：`acl_rule.sequence`（top / dest_rule_id / bottom）显式链式排序，
  实现「先拒绝 SSH/RDP → 放行 ICMP → 放行指定域名 → 默认拒绝」的可读顺序。
- **双日志同目标**：CFW 单条 allow 规则同时记录放行与拒绝；LTS 中 `cfw-access` / `cfw-flow`
  流可关联同一目标的放行与拒绝事件，便于回溯。
- **EIP 直出 + CFW 保护对象**：workload ECS 绑管理 EIP 出网，EIP 通过 `cfw_eip_protection`
  纳入防火墙，无需 NAT 网关，部署模型简单清晰。
- **离线可复现**：`.terraformrc` + dev_overrides 提供本地 provider 缓存，
  `terraform init` / `validate` / `apply` 全程可离线完成。

---

## 5. 涉及云服务

| 云服务 | 作用 | 备注 |
|---|---|---|
| 虚拟私有云 VPC | 提供隔离网络环境 | 单 VPC 单子网 |
| 弹性云服务器 ECS | 作为 workload 出网载体 | s6.large.2 |
| 弹性公网 IP EIP | 提供 ECS 管理与出网入口 | CFW 保护对象 |
| 云防火墙 CFW | 互联网边界流量检查与排序 | postPaid 按需 |
| 云日志服务 LTS | 承接 CFW 日志与 VPC 流日志 | cfw-logs / vpc-flowlog |

---

## 6. 前置条件

- Terraform >= 1.3（验证用 1.10），`huaweicloud` provider v1.96.0
- 华为云账号（默认 region `cn-north-4`），具备 VPC/CFW/LTS/ECS 权限
- `HW_ACCESS_KEY` / `HW_SECRET_KEY` / `HW_REGION_NAME` 环境变量（凭据仅通过环境变量提供，不要写入代码或配置文件）
- 本地已缓存 `huaweicloud` v1.96.0 provider

> 区域说明：CFW 按需（postPaid）模式仅部分区域支持（如 ap-southeast-1）。
> 若目标区域不支持按需模式，请改用订阅模式或调整区域。

---

## 7. 快速开始

```bash
cd infra
export TF_CLI_CONFIG_FILE=.terraformrc
export HW_ACCESS_KEY=<你的AK> HW_SECRET_KEY=<你的SK> HW_REGION_NAME=cn-north-4
terraform init
terraform validate
terraform plan
terraform apply
```

---

## 8. 分步部署

1. **环境准备**：安装 Terraform 与 `huaweicloud` provider；配置环境变量 `HW_ACCESS_KEY` /
   `HW_SECRET_KEY` / `HW_REGION_NAME`。
2. **进入 infra 目录**：`cd infra`，设置 `TF_CLI_CONFIG_FILE=.terraformrc`。
3. **terraform init**：初始化 provider（走本地缓存，避免重复下载）。
4. **terraform validate**：校验语法与 provider 版本约束。
5. **terraform plan**：确认将创建的资源（VPC / 子网 / EIP / ECS / CFW / LTS / 6 条 acl_rule）。
6. **terraform apply**：确认 plan 后执行；返回 0 即部署成功。
7. **查看资源**：控制台「云防火墙 > 访问控制 > 互联网边界」核对 6 条规则顺序；
   「云日志服务 LTS」核对 `cfw-logs-<id>` 与 `vpc-flowlog-<id>` 日志组。

---

## 9. 使用方法 / 验证

### 使用方法


1. 控制台「云防火墙 > 访问控制 > 互联网边界」确认 6 条规则按既定顺序生效。
2. 由 workload 子网产生外访流量（建议用不带 EIP 的 ECS，或临时解绑 EIP）：
- 访问 `example.com`(HTTP) / `example.net`(HTTPS) → 放行并记录；
- 访问其他域名/端口 → 被 `deny-all` 拒绝。
3. LTS 的 `cfw-logs-<id>` 日志组下查看 `cfw-access` / `cfw-flow`，确认放行与拒绝均被记录。
4. VPC Flow Logs 落在 `vpc-flowlog-<id>` 日志组。

详见 `docs/architecture.md` 与 `docs/deployment-guide.md`。

部署完成后请按本节步骤自行验证，确认业务功能可用，方可视为交付完成。

---

## 10. 清理资源

```bash
cd infra
terraform destroy
```

- 销毁前再次确认 `HW_ACCESS_KEY` / `HW_SECRET_KEY` 与目标 region。
- CFW、EIP、LTS 等删除后请到控制台确认无残留（CFW 实例删除可能需先解绑保护对象）。
- 销毁为最终清理动作，不可恢复；如需保留中间数据请提前导出。

---

## 11. 详细说明

- 目录结构与各 .tf 文件职责详见「目录结构」节。
- 架构细节、acl_rule 顺序、CFW 保护对象机制、LTS 双日志落点：
  `docs/architecture.md`。
- 部署流程、命令清单、清理要点：`docs/deployment-guide.md`。

---

## 12. 依赖

- 本实践基于华为云 CFW / LTS / VPC / ECS / EIP 服务，遵循华为云产品文档。

---

## 13. FAQ / 故障排除

### FAQ


- **Q：为什么不用 NAT 网关？**
  A：本实践强调「EIP 直出 + CFW 保护对象」的最简部署模型；如需 NAT 出网，请改用
  `huaweicloud_nat_gateway` 并将 NAT EIP 加入 CFW 保护对象。
- **Q：CFW 按需模式 region 限制？**
  A：按需（postPaid）模式仅部分 region 支持（如 `ap-southeast-1`）；其他 region
  请改用订阅模式或在控制台手动调整。
- **Q：如何调整规则顺序？**
  A：修改 `infra/firewall.tf` 中各 `huaweicloud_cfw_acl_rule.sequence` 块（top / bottom /
  dest_rule_id），再 `terraform apply`。
- **Q：日志看不到拒绝事件？**
  A：确认 `cfw_lts_log.cfw` 已开启 `lts_access_log_stream_enable` / `lts_flow_log_stream_enable`
  / `lts_attack_log_stream_enable`；CFW 默认会同时记录放行与拒绝。

---

## 14. 贡献指南

- 本仓库以「合规 + 可复现」为首要目标；任何 PR 必须保留 LICENSE 与 README 编号结构。
- 修改 .tf 时请勿改动既有 `resource` / `data` / `output` 块，仅允许在头部注释中
  添加必要的说明文字。

---

## 15. 许可证

本实践采用 **MIT No Attribution** 许可证，详见根目录 `LICENSE` 文件。

---

## 16. 联系方式 / 维护者
| 项 | 内容 |
|---|---|
| **创建者** | [dgc-git](https://github.com/dgc-git) |
| **维护者** | [dgc-git](https://github.com/dgc-git) |
| **联系方式** | GitHub Issues / PR（见[第 14 节](#14-贡献指南)） |
