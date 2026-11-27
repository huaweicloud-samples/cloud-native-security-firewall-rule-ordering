# 部署指导书 — 云防火墙严格规则排序（日志示例）

## 前置条件

- 已安装 Terraform >= 1.3（本实践用 1.10 验证；provider `huaweicloud` v1.96.0）。
- 华为云账号（目标 region 默认 `cn-north-4`），具备 VPC / CFW / LTS / ECS 创建权限。
- 配置 `HW_ACCESS_KEY` / `HW_SECRET_KEY` / `HW_REGION_NAME` 环境变量（**禁止硬编码进 .tf**）。
- 本地已缓存 `huaweicloud` v1.96.0 provider（离线校验用 `infra/.terraformrc` 的 dev_overrides）。

> 区域说明：CFW 按需（postPaid）模式仅部分区域支持（如 ap-southeast-1）。
> 若目标区域不支持按需模式，请改用订阅模式或调整区域。

## 快速开始

```bash
cd infra
export TF_CLI_CONFIG_FILE=.terraformrc # 离线使用本地 provider 缓存
export HW_ACCESS_KEY=<你的AK> # 仅经环境变量注入，不落盘
export HW_SECRET_KEY=<你的SK>
export HW_REGION_NAME=cn-north-4

terraform init
terraform validate # 已通过（仅 dev_overrides 警告）
terraform plan # 确认资源
terraform apply
```

## 验证 CFW 严格规则排序与双日志

1. `terraform apply` 成功后，控制台进入「云防火墙 > 访问控制 > 互联网边界」，确认 6 条规则按
deny-ssh → deny-rdp → allow-icmp → allow-example → allow-example-net → deny-all 顺序生效。
2. 由 workload ECS 产生外访流量，访问 `example.com`(HTTP) 与 `example.net`(HTTPS)
应被放行并记录；访问其他域名/端口应被 deny-all 拒绝。
3. 在「云日志服务 LTS」的 `cfw-logs-<id>` 日志组下查看 `cfw-access` / `cfw-flow` 流，确认**放行与拒绝**
均被记录（放行/拒绝同目标双日志）。
4. VPC Flow Logs 落在 `vpc-flowlog-<id>` 日志组。

## 清理

```bash
terraform destroy
```
注意：CFW、EIP、LTS 等删除后请到控制台确认无残留（CFW 实例删除可能需先解绑保护对象）。
