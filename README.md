# S-Hy2 Manager

Hysteria2 服务器端部署与管理脚本。

## 快速安装

```bash
curl -fsSL https://raw.githubusercontent.com/Sakura-wcs/hysteria2_VPS_Install/main/quick-install.sh | sudo bash
sudo s-hy2
```

## 手动安装

```bash
git clone https://github.com/Sakura-wcs/hysteria2_VPS_Install.git
cd hysteria2_VPS_Install
chmod +x hy2-manager.sh install.sh quick-install.sh scripts/*.sh
sudo ./hy2-manager.sh
```

## 功能

- 安装 / 更新 Hysteria2
- 主菜单管理
- 证书管理
- 出站规则管理
- 防火墙管理
- 菜单内更新管理脚本
- 节点与订阅信息
- 服务管理

## 证书说明

证书管理支持：

- 自签名证书
- 手动上传证书
- 按域名搜索并同步证书到固定目录
- 可选 crontab 定时同步，默认每天 04:00

## 维护说明

本仓库以维护和适配最新 Hysteria2 内核为目标，安装和升级仍使用官方脚本：

`https://get.hy2.sh/`

## 贡献

提交 issue 或 pull request 即可。
