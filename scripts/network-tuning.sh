#!/usr/bin/env bash

NETWORK_SYSCTL_FILE="${SYSCTL_CONF:-/etc/sysctl.d/99-s-hy2-network.conf}"
NETWORK_SYSCTL_BIN="${SYSCTL_BIN:-sysctl}"

network_current_qdisc() {
    "$NETWORK_SYSCTL_BIN" -n net.core.default_qdisc 2>/dev/null || true
}

network_current_congestion_control() {
    "$NETWORK_SYSCTL_BIN" -n net.ipv4.tcp_congestion_control 2>/dev/null || true
}

network_bbr_available() {
    local available
    available="$("$NETWORK_SYSCTL_BIN" -n net.ipv4.tcp_available_congestion_control 2>/dev/null || true)"
    [[ " $available " == *" bbr "* ]]
}

network_bbr_fq_configured() {
    [[ "$(network_current_qdisc)" == "fq" ]] && [[ "$(network_current_congestion_control)" == "bbr" ]]
}

network_show_status() {
    local qdisc congestion
    qdisc="$(network_current_qdisc)"
    congestion="$(network_current_congestion_control)"

    echo "当前队列规则: ${qdisc:-未知}"
    echo "当前拥塞控制: ${congestion:-未知}"
    if network_bbr_fq_configured; then
        echo "状态: BBR 和 FQ 已启用"
    elif network_bbr_available; then
        echo "状态: 可启用 BBR 和 FQ"
    else
        echo "状态: 当前内核未报告 BBR 可用"
    fi
}

network_write_bbr_fq() {
    local parent
    parent="$(dirname "$NETWORK_SYSCTL_FILE")"
    mkdir -p "$parent" || return 1
    chmod 755 "$parent" 2>/dev/null || true

    printf '%s\n' \
        '# Managed by S-Hy2. Remove this file to restore system defaults.' \
        'net.core.default_qdisc=fq' \
        'net.ipv4.tcp_congestion_control=bbr' > "$NETWORK_SYSCTL_FILE" || return 1
    chmod 644 "$NETWORK_SYSCTL_FILE" || return 1

    "$NETWORK_SYSCTL_BIN" -p "$NETWORK_SYSCTL_FILE"
}

network_manage_bbr_fq() {
    echo ""
    echo "=== BBR / FQ 网络调优 ==="
    network_show_status
    echo ""

    if network_bbr_fq_configured; then
        return 0
    fi

    if ! network_bbr_available; then
        echo "当前内核不支持 BBR，未修改系统设置。"
        return 1
    fi

    echo "将写入: $NETWORK_SYSCTL_FILE"
    echo -n "是否启用 BBR 和 FQ? [y/N]: "
    local choice
    read -r choice
    [[ "$choice" =~ ^[Yy]$ ]] || return 0

    if network_write_bbr_fq && network_bbr_fq_configured; then
        echo "BBR 和 FQ 已启用并完成复检。"
        return 0
    fi

    echo "应用 BBR/FQ 失败，请检查内核支持和 sysctl 输出。"
    return 1
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    network_manage_bbr_fq
fi
