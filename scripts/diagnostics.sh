#!/usr/bin/env bash

if ! declare -F config_validate_with_core >/dev/null; then
    # shellcheck source=/dev/null
    source "$(dirname "${BASH_SOURCE[0]}")/config-validator.sh"
fi

DIAGNOSTIC_CONFIG_PATH="${DIAGNOSTIC_CONFIG:-${CONFIG_PATH:-/etc/hysteria/config.yaml}}"
DIAGNOSTIC_HYSTERIA_BIN="${HYSTERIA_BIN:-hysteria}"
DIAGNOSTIC_SERVICE_NAME="${SERVICE_NAME:-hysteria-server.service}"
DIAGNOSTIC_RESULTS=""
DIAGNOSTIC_REPAIRABLE=""

diagnostic_add() {
    local id="$1" status="$2" message="$3" repair="${4:-}"
    DIAGNOSTIC_RESULTS+="${id}:${status}:${message}"$'\n'
    [[ -n "$repair" ]] && DIAGNOSTIC_REPAIRABLE+="${repair}"$'\n'
}

diagnostic_config_port() {
    sed -n 's/^[[:space:]]*listen:[[:space:]]*.*:\([0-9][0-9]*\).*/\1/p' "$DIAGNOSTIC_CONFIG_PATH" | head -1
}

diagnostic_check_config() {
    if [[ ! -f "$DIAGNOSTIC_CONFIG_PATH" ]]; then
        diagnostic_add config error "配置文件不存在: $DIAGNOSTIC_CONFIG_PATH"
        return
    fi

    if config_validate_with_core "$DIAGNOSTIC_CONFIG_PATH" >/dev/null 2>&1; then
        diagnostic_add config ok "配置语法和当前内核兼容"
    else
        diagnostic_add config error "配置语法错误或与当前内核不兼容"
    fi
}

diagnostic_check_binary() {
    if command -v "$DIAGNOSTIC_HYSTERIA_BIN" >/dev/null 2>&1 || [[ -x "$DIAGNOSTIC_HYSTERIA_BIN" ]]; then
        diagnostic_add binary ok "Hysteria2 二进制可执行"
    else
        diagnostic_add binary error "未找到 Hysteria2 二进制"
    fi
}

diagnostic_check_service() {
    if ! command -v systemctl >/dev/null 2>&1; then
        diagnostic_add service warning "系统未提供 systemctl，无法检测服务"
    elif systemctl is-active --quiet "$DIAGNOSTIC_SERVICE_NAME"; then
        diagnostic_add service ok "服务正在运行"
    else
        diagnostic_add service error "服务未运行" service-enable-start
    fi
}

diagnostic_check_permissions() {
    [[ -f "$DIAGNOSTIC_CONFIG_PATH" ]] || return

    local mode
    mode="$(stat -c '%a' "$DIAGNOSTIC_CONFIG_PATH" 2>/dev/null || true)"
    if [[ "$mode" == "600" ]]; then
        diagnostic_add permissions ok "配置文件权限为 600"
    else
        diagnostic_add permissions warning "配置文件权限应为 600，当前为 ${mode:-未知}" file-permissions
    fi
}

diagnostic_check_listener() {
    [[ -f "$DIAGNOSTIC_CONFIG_PATH" ]] || return

    local port listeners
    port="$(diagnostic_config_port)"
    [[ -n "$port" ]] || {
        diagnostic_add listener warning "未能从配置读取 UDP 监听端口"
        return
    }

    listeners="$(ss -H -lun 2>/dev/null | awk -v port=":$port" '$5 ~ (port "$") { print }')"
    if [[ -n "$listeners" ]]; then
        diagnostic_add listener ok "UDP 端口 $port 正在监听"
    else
        diagnostic_add listener warning "UDP 端口 $port 未监听；请检查服务日志"
    fi
}

diagnostic_check_acme() {
    [[ -f "$DIAGNOSTIC_CONFIG_PATH" ]] || return
    grep -q '^[[:space:]]*acme:' "$DIAGNOSTIC_CONFIG_PATH" || return

    if grep -A 12 '^[[:space:]]*acme:' "$DIAGNOSTIC_CONFIG_PATH" | grep -qE '^[[:space:]]*-[[:space:]]*[^[:space:]]+'; then
        diagnostic_add acme ok "ACME 域名已配置；DNS 和签发结果需由用户确认"
    else
        diagnostic_add acme error "ACME 已启用但未配置域名"
    fi
}

diagnostic_check_network() {
    if declare -F network_bbr_fq_configured >/dev/null; then
        if network_bbr_fq_configured; then
            diagnostic_add network ok "BBR 和 FQ 已启用"
        else
            diagnostic_add network warning "BBR 或 FQ 未启用" network-bbr-fq
        fi
    else
        diagnostic_add network warning "未加载网络调优模块"
    fi
}

diagnostic_check_firewall() {
    if declare -F detect_firewall >/dev/null && declare -F smart_manage_hysteria_port >/dev/null; then
        diagnostic_add firewall warning "请确认 UDP 端口已在防火墙放行" firewall-udp
    else
        diagnostic_add firewall warning "防火墙模块未加载，无法自动修复"
    fi
}

diagnostic_collect() {
    DIAGNOSTIC_RESULTS=""
    DIAGNOSTIC_REPAIRABLE=""
    diagnostic_check_binary
    diagnostic_check_config
    diagnostic_check_service
    diagnostic_check_permissions
    diagnostic_check_listener
    diagnostic_check_acme
    diagnostic_check_firewall
    diagnostic_check_network
}

diagnostic_repair() {
    case "$1" in
        service-enable-start)
            systemctl enable --now "$DIAGNOSTIC_SERVICE_NAME"
            ;;
        file-permissions)
            if declare -F set_hysteria_file_permissions >/dev/null; then
                set_hysteria_file_permissions "$DIAGNOSTIC_CONFIG_PATH"
            else
                chmod 600 "$DIAGNOSTIC_CONFIG_PATH"
            fi
            ;;
        network-bbr-fq)
            network_write_bbr_fq
            ;;
        firewall-udp)
            smart_manage_hysteria_port
            ;;
        *)
            return 64
            ;;
    esac
}

diagnostic_show() {
    local line id status message selected_repair
    diagnostic_collect
    echo ""
    echo "=== Hysteria2 配置自检 ==="
    while IFS= read -r line; do
        [[ -n "$line" ]] || continue
        IFS=: read -r id status message <<< "$line"
        case "$status" in
            ok) printf '[OK] %s\n' "$message" ;;
            warning) printf '[WARN] %s\n' "$message" ;;
            *) printf '[ERROR] %s\n' "$message" ;;
        esac
    done <<< "$DIAGNOSTIC_RESULTS"

    [[ -n "$DIAGNOSTIC_REPAIRABLE" ]] || return 0
    echo ""
    echo "可修复项目:"
    local repairs=() choice
    while IFS= read -r line; do
        [[ -n "$line" ]] && repairs+=("$line")
    done <<< "$DIAGNOSTIC_REPAIRABLE"
    for ((choice = 0; choice < ${#repairs[@]}; choice++)); do
        printf ' %d. %s\n' "$((choice + 1))" "${repairs[choice]}"
    done
    echo " 0. 返回"
    echo -n "选择要修复的项目 [0-${#repairs[@]}]: "
    read -r choice
    [[ "$choice" =~ ^[0-9]+$ ]] || return 0
    ((choice > 0 && choice <= ${#repairs[@]})) || return 0
    selected_repair="${repairs[choice - 1]}"
    echo -n "确认修复 ${selected_repair}? [y/N]: "
    read -r choice
    [[ "$choice" =~ ^[Yy]$ ]] && diagnostic_repair "$selected_repair"
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    diagnostic_show
fi
