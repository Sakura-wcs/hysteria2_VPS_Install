#!/bin/bash

# Hysteria2 配置管理脚本一键安装脚本
# 使用方法: curl -fsSL https://raw.githubusercontent.com/Sakura-wcs/hysteria2_VPS_Install/main/quick-install.sh | sudo bash
# 调试模式: curl -fsSL https://raw.githubusercontent.com/Sakura-wcs/hysteria2_VPS_Install/main/quick-install.sh | sudo bash -s -- --debug

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

log_error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}
# 脚本信息
INSTALL_DIR="/opt/s-hy2"
BIN_DIR="/usr/local/bin"
RAW_URL="https://raw.githubusercontent.com/Sakura-wcs/hysteria2_VPS_Install"

# 打印标题
print_header() {
    clear
    echo -e "${CYAN}================================================${NC}"
    echo -e "${CYAN}    Hysteria2 配置管理脚本一键安装${NC}"
    echo -e "${CYAN}================================================${NC}"
    echo ""
}

# 检查是否为 root 用户
check_root() {
    if [[ $EUID -ne 0 ]]; then
        echo -e "${RED}错误: 此脚本需要 root 权限运行${NC}"
        echo "请使用 sudo 运行此脚本"
        return 1
    fi
    return 0
}

# 检测系统类型
detect_system() {
    if [[ -f /etc/os-release ]]; then
        source /etc/os-release
        OS=$ID
        VER=$VERSION_ID
        echo -e "${BLUE}检测到系统: $PRETTY_NAME${NC}"
        return 0
    else
        echo -e "${RED}无法检测系统类型${NC}"
        return 1
    fi
}

# 安装依赖
install_dependencies() {
    echo -e "${BLUE}安装必要依赖...${NC}"

    case $OS in
        ubuntu|debian)
            echo "更新软件包列表..."
            if ! apt update; then
                echo -e "${YELLOW}警告: 软件包列表更新失败，继续安装...${NC}"
            fi
            echo "安装依赖包..."
            if ! apt install -y curl wget git openssl net-tools iptables python3 python3-yaml; then
                echo -e "${YELLOW}警告: 部分依赖安装失败，继续执行...${NC}"
            fi
            ;;
        centos|rhel|fedora)
            if command -v dnf &> /dev/null; then
                echo "使用 dnf 安装依赖..."
                if ! dnf install -y curl wget git openssl net-tools iptables python3 python3-pyyaml; then
                    echo -e "${YELLOW}警告: 部分依赖安装失败，继续执行...${NC}"
                fi
            else
                echo "使用 yum 安装依赖..."
                if ! yum install -y curl wget git openssl net-tools iptables python3 python3-pyyaml; then
                    echo -e "${YELLOW}警告: 部分依赖安装失败，继续执行...${NC}"
                fi
            fi
            ;;
        *)
            echo -e "${YELLOW}未知系统，跳过依赖安装...${NC}"
            ;;
    esac

}

# The piped bootstrap needs only this module before invoking the shared deployer.
quick_install_manager() (
    local checkout="${1:-}" module temp='' revision
    export MANAGER_UPDATE_INSTALL_DIR="$INSTALL_DIR" MANAGER_UPDATE_BIN_DIR="$BIN_DIR"
    if [[ -n "$checkout" ]]; then
        module="$checkout/scripts/manager-update.sh"
    else
        revision="$(curl -fsSL --proto '=https' --proto-redir '=https' --connect-timeout 8 --max-time 30 \
            -H 'Accept: application/vnd.github.sha' \
            https://api.github.com/repos/Sakura-wcs/hysteria2_VPS_Install/commits/main)" || return 1
        [[ "$revision" =~ ^[0-9a-f]{40}$ ]] || { log_error '未获取到有效的上游提交。'; return 1; }
        export MANAGER_UPDATE_RAW_URL="$RAW_URL/$revision"
        temp="$(mktemp -d)" || return 1
        trap 'rm -rf -- "$temp"' EXIT
        module="$temp/manager-update.sh"
        curl -fsSL --proto '=https' --proto-redir '=https' --connect-timeout 8 --max-time 30 \
            "$MANAGER_UPDATE_RAW_URL/scripts/manager-update.sh" -o "$module" || return 1
    fi
    bash -n "$module" && source "$module" && manager_deploy "$checkout"
)
# 显示安装完成信息
show_completion() {
    echo ""
    echo -e "${CYAN}================================================${NC}"
    echo -e "${CYAN}    Hysteria2 配置管理脚本安装完成!${NC}"
    echo -e "${CYAN}================================================${NC}"
    echo ""
    echo -e "${GREEN}安装位置:${NC} $INSTALL_DIR"
    echo -e "${GREEN}命令快捷方式:${NC} s-hy2, hy2-manager"
    echo ""
    echo -e "${YELLOW}使用方法:${NC}"
    echo "  方式1: 快捷命令 (推荐)"
    echo "    sudo s-hy2"
    echo ""
    echo "  方式2: 完整命令"
    echo "    sudo hy2-manager"
    echo ""
    echo -e "${YELLOW}快速开始:${NC}"
    echo "1. 运行: sudo s-hy2"
    echo "2. 打开「安装与更新」安装核心"
    echo "3. 打开「配置管理」创建配置，再在「节点与订阅」查看连接信息"
    echo ""
    echo -e "${BLUE}现在可以运行 'sudo s-hy2' 开始使用!${NC}"
    echo ""
}

# 简化的确认函数 - 直接安装或交互确认
confirm_installation() {
    # 检查是否通过管道运行
    if [[ -t 0 ]]; then
        # 标准输入可用，可以进行交互
        echo -n -e "${YELLOW}是否继续安装? [Y/n]: ${NC}"
        read -r confirm
        if [[ $confirm =~ ^[Nn]$ ]]; then
            echo -e "${BLUE}取消安装${NC}"
            exit 0
        fi
    else
        # 通过管道运行，检查是否有强制参数
        if [[ "$1" != "--force" && "$1" != "-f" ]]; then
            echo -e "${YELLOW}检测到通过管道运行脚本，开始安装...${NC}"
        else
            echo -e "${BLUE}强制模式，跳过确认${NC}"
        fi
    fi
}

main() {
    local checkout=''
    case "${1:-}" in
        --debug) set -x ;;
        --uninstall)
            check_root || return 1
            export MANAGER_UPDATE_INSTALL_DIR="$INSTALL_DIR" MANAGER_UPDATE_BIN_DIR="$BIN_DIR"
            if [[ ! -r "$INSTALL_DIR/scripts/manager-update.sh" ]] ||
                ! source "$INSTALL_DIR/scripts/manager-update.sh" ||
                ! declare -F manager_uninstall >/dev/null; then
                log_error '未安装当前版本的管理器；如仍在使用旧版本，请先升级。'
                return 1
            fi
            manager_uninstall
            return ;;
        ''|--force|-f) ;;
        *) log_error "未知选项: $1"; return 1 ;;
    esac

    check_root || return 1
    print_header
    confirm_installation "${1:-}"
    detect_system || return 1
    install_dependencies
    command -v curl >/dev/null && command -v systemctl >/dev/null || {
        log_error '缺少 curl 或 systemctl，无法完成安装。'
        return 1
    }
    python3 -c 'import yaml' >/dev/null 2>&1 ||
        echo -e "${YELLOW}警告: 缺少 Python 3 或 PyYAML，高级配置探测不可用。${NC}" >&2

    if [[ -f "${BASH_SOURCE[0]:-}" ]]; then
        checkout="$(cd "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)" || return 1
        [[ -f "$checkout/scripts/manager-update.sh" ]] || checkout=''
    fi
    quick_install_manager "$checkout" || {
        log_error '安装失败，未启用新版本。'
        return 1
    }
    show_completion
}

if [[ -z "${BASH_SOURCE[0]:-}" || "${BASH_SOURCE[0]}" == "$0" ]]; then
    main "$@"
fi
