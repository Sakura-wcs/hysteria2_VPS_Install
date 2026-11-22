# S-Hy2 Manager

用于部署和维护 Hysteria 2 服务端的 Bash 管理脚本。核心安装与更新始终使用 Hysteria 官方安装器，版本信息来自官方 `apernet/hysteria` Release。

## 安装

在支持 systemd 的 Linux 上运行。快速安装只部署 `s-hy2` 管理器；首次安装 Hysteria2 核心，请运行 `sudo s-hy2`，进入「安装与更新 → 安装 Hysteria2」。

```bash
curl -fsSL https://raw.githubusercontent.com/Sakura-wcs/hysteria2_VPS_Install/main/quick-install.sh | sudo bash
sudo s-hy2
```

也可以克隆仓库后执行：

```bash
git clone https://github.com/Sakura-wcs/hysteria2_VPS_Install.git
cd hysteria2_VPS_Install
sudo bash ./quick-install.sh
```

管道安装无需交互确认；从终端直接运行脚本会询问是否继续。安装后可用 `sudo s-hy2` 或 `sudo hy2-manager` 打开同一管理器。

## 菜单

- 安装与更新：安装核心，检查 Release 版本；相同版本不会重复更新，可明确选择强制重装。
- 配置管理：在「创建或重置配置」中选择快速或手动配置，确认后再执行；也可以修改现有配置，或进入「高级配置」编辑完整 YAML。
- 服务与诊断：检查核心、配置启动探测、权限、服务状态、UDP 监听、ACME 基础配置、防火墙和 BBR/FQ；可选修复需确认。
- 网络与系统：检测并配置 BBR 与 FQ。
- 节点与订阅：生成安全编码的 URI、客户端 YAML 和 JSON 配置。
- 证书与域名：进入后选择证书或域名，只打开所选子菜单。出站和防火墙也按需加载。

## 高级配置

完整 YAML 编辑统一从「配置管理 → 高级配置」进入。编辑器优先使用 `VISUAL` 或 `EDITOR`，未设置时依次尝试 `nano`、`vi`、`vim`。替换前会用内核短暂启动一份临时配置：Hysteria UDP 监听改到 `127.0.0.1:0`，不启动流量统计、伪装 HTTP/HTTPS 监听或 Mimic，并检查内核是否报告启动成功。探测不会验证这些被关闭的功能、实际端口、服务用户权限或 systemd 工作目录；ACME 等运行时依赖仍可能产生网络请求或影响结果。

该探测需要 Python 3 和 PyYAML。快速安装会尝试安装；如果从旧版通过菜单更新，请检查系统是否有 `python3-yaml`（Debian/Ubuntu）或 `python3-pyyaml`（Fedora/RHEL）。缺少依赖时，脚本会拒绝未经验证的配置修改。

探测失败时不会改动当前配置；通过后才会备份并以同目录替换方式写入。完整编辑会保留内核支持但尚未提供表单的字段。

常用字段可直接修改：监听地址、是否忽略客户端带宽、UDP 空闲超时和禁用 UDP。ACL 是一个配置块，不是单一文件路径；可通过完整 YAML 编辑其规则和文件路径，或使用出站规则菜单。带宽、TLS/ACME、认证、混淆和伪装也可通过完整 YAML 编辑。

## 自检与修复

自检可在确认后启用或启动服务、修正配置权限、放行 UDP 端口或写入 BBR/FQ 设置。ACME 检查只验证域名配置是否存在，不验证 DNS 或签发结果；UDP 检查不会终止其他进程。

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

在菜单“关于与脚本更新”中选择“更新管理脚本”。快速安装和更新共用运行文件清单：在线下载锁定到同一 GitHub 提交，完整暂存后逐个检查 Bash 文件，再替换安装目录。启用失败时会尝试恢复旧安装；备份路径会显示在终端。更新不会改动 `/etc/hysteria` 配置或自动更新核心。

新版不再安装独立配置模板、旧性能基准工具和旧部署自检脚本。配置及节点输出由现有模块生成，服务自检从菜单进入。仓库里的 `config/app.conf`、`scripts/config-loader.sh` 和 `scripts/post-deploy-check.sh` 仅为旧版更新器保留原下载路径，不属于新版安装清单。从旧版用菜单升级后，旧文件可能仍在安装目录；下一次使用新版更新器或新版快速安装器时，旧目录会整体留在备份中。

## 卸载

管理菜单可分别卸载核心或管理器。卸载核心使用官方卸载器，保留 `/etc/hysteria`、证书和共享系统依赖；卸载管理器则保留核心和配置，把管理器目录移到终端显示的备份位置。项目不再创建桌面快捷方式，也不再批量移除 Nginx、系统依赖或防火墙规则。旧安装留下的桌面快捷方式及端口跳跃规则请在确认用途后单独清理。
