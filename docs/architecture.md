# 架构说明 — 云防火墙严格规则排序（日志示例）

本实践在华为云上演示**云防火墙（CFW）严格规则排序**：按既定顺序拒绝 SSH/RDP、放行 ICMP、
放行指定域名（HTTP/HTTPS），其余流量默认拒绝；同时把放行与拒绝流量分别记录到 LTS，实现
「放行/拒绝同目标」的双日志效果。

## 目标架构

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
> 因此 ECS 的外访流量经 CFW 检查后放行或拒绝。本实践**不使用 NAT 网关**（见「设计要点」）。

## 设计要点

| 维度 | 方案 |
|---|---|
| 防火墙部署 | CFW 集中式：防火墙实例 + 绑定受保护 EIP（互联网边界），无 inspection 子网 / 路由表操纵 |
| 严格排序 | `acl_rule.sequence`（top → dest_rule_id 链 → bottom）实现规则优先级链 |
| 规则语义 | 结构化 `acl_rule`；放行规则同时记录日志（CFW 同时记录放行与拒绝） |
| 域名匹配 | `address_type=1` 域名规则（`destination_domain_address_name`，匹配主域及子域） |
| 日志 | CFW 访问/流/攻击日志 + VPC Flow Logs 均入 LTS |
| 实例管理 | ECS 绑定 EIP（管理面），便于 SSH 登录与演示 |

### CFW acl_rule 顺序（严格规则排序）

1. `deny-ssh`（TCP/22）← top
2. `deny-rdp`（TCP/3389）
3. `allow-icmp`（ICMP）
4. `allow-example-com`（HTTP/80，域名 `example.com`）
5. `allow-example-net`（HTTPS/443，域名 `example.net`）
6. `deny-all` ← bottom（默认拒绝）

## 验证路径注意事项

- ECS 直接绑定 EIP 时，其主动外访流量经 EIP 出网并被 CFW 检查，可直接观察严格规则排序与双日志。
- 若 ECS 有多个外访出口（如后续增加 NAT），需保证外访流量均经 CFW 保护对象路径，否则无法覆盖。

## 资源清单（infra/）

- `vpc.tf`：VPC、workload 子网、ECS 管理 EIP（无 NAT）。
- `firewall.tf`：`cfw_firewall`（按需 postPaid）+ `cfw_eip_protection`（保护 ECS EIP）+ `cfw_acl_rule`（6 条，sequence 排序）。
- `logging.tf`：LTS 日志组/流、CFW→LTS 日志、VPC Flow Log→LTS。
- `compute.tf`：ECS 镜像数据源、安全组及规则、workload ECS（绑管理 EIP，系统盘不加密）。
