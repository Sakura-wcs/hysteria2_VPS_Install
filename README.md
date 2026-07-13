# S-Hy2 Manager

用于部署和维护 Hysteria 2 服务端的 Bash 管理脚本。核心安装与更新始终使用 Hysteria 官方安装器，版本信息来自官方 `apernet/hysteria` Release。

## 安装

```bash
curl -fsSL https://raw.githubusercontent.com/Sakura-wcs/hysteria2_VPS_Install/main/quick-install.sh | sudo bash
sudo s-hy2
```

也可以克隆仓库后执行：

```bash
git clone https://github.com/Sakura-wcs/hysteria2_VPS_Install.git
cd hysteria2_VPS_Install
sudo ./quick-install.sh
```

## 菜单

- 安装与更新：安装核心，检查 Release 版本；相同版本不会重复更新，可明确选择强制重装。
- 配置管理：将“快速配置”和“手动配置”收进“创建或重置配置”，执行前会二次确认；现有配置修改和高级配置独立。
- 服务与诊断：服务管理、配置语法/权限/服务状态/监听端口/ACME/防火墙/BBR-FQ 自检，以及可确认的修复项。
- 网络与系统：检测并配置 BBR 与 FQ。
- 节点与订阅：生成安全编码的 URI、客户端 YAML 和 JSON 配置。
- 证书与域名、出站与防火墙：按需加载对应管理模块。

## 高级配置

高级配置支持完整 YAML 编辑。脚本会在替换前调用：

```bash
hysteria config check /path/to/candidate.yaml
```

校验失败时不会改动当前配置；校验通过后才会备份并以同目录原子替换方式写入。完整编辑会保留 Hysteria 当前内核支持但脚本尚未提供表单的官方字段。

常用字段可直接修改：监听地址、是否忽略客户端带宽、UDP 空闲超时、禁用 UDP 与 ACL 路径。带宽、TLS/ACME、认证、混淆、伪装、出站和路由可通过完整 YAML 编辑。

## 自检与修复

自检会检查二进制、配置语法、服务状态、配置权限、UDP 监听、ACME 基础配置、可用防火墙模块和 BBR/FQ。

只有确定且非破坏性的项目允许确认后修复：启用/启动服务、修正配置权限、放行防火墙端口、写入 BBR/FQ 设置。DNS 解析、ACME 签发失败与端口被其他服务占用只会报告，不会自动修改或终止其他服务。

BBR/FQ 设置仅写入：

```text
/etc/sysctl.d/99-s-hy2-network.conf
```

不会覆盖其他 sysctl 文件。

## 节点输出

节点 URI 始终显式包含 `insecure=0` 或 `insecure=1`。默认不会跳过证书验证；只有自签名证书或用户明确选择跳过验证时才使用 `1`。认证密码与 Salamander 密码会进行 URI 百分号编码，并在 YAML/JSON 中转义和引用。

## 官方来源

- Hysteria 文档：[完整服务端配置](https://v2.hysteria.network/zh/docs/advanced/Full-Server-Config/)
- 上游核心：[apernet/hysteria](https://github.com/apernet/hysteria)
- 官方安装器：[get.hy2.sh](https://get.hy2.sh/)

## 更新管理脚本

在菜单“关于与脚本更新”中选择“更新管理脚本”。更新器只下载脚本运行所需的受控文件清单，校验 Bash 语法、备份当前安装目录后再替换，不会改动 `/etc/hysteria` 配置或自动更新核心。
