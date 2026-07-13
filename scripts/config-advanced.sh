#!/usr/bin/env bash

config_advanced_target() {
    printf '%s' "${CONFIG_ADVANCED_PATH:-${CONFIG_PATH:-/etc/hysteria/config.yaml}}"
}

config_advanced_binary() {
    printf '%s' "${HYSTERIA_BIN:-hysteria}"
}

config_advanced_apply() {
    local candidate="$1" target binary target_dir replacement backup
    target="$(config_advanced_target)"
    binary="$(config_advanced_binary)"
    target_dir="$(dirname "$target")"

    [[ -f "$candidate" ]] || return 1
    "$binary" config check "$candidate" || return 1
    mkdir -p "$target_dir" || return 1

    replacement="$(mktemp "$target_dir/.config.yaml.s-hy2.XXXXXX")" || return 1
    if ! install -m 600 "$candidate" "$replacement"; then
        rm -f "$replacement"
        return 1
    fi

    if [[ -f "$target" ]]; then
        backup="${target}.backup.$(date +%Y%m%d_%H%M%S)"
        cp -a "$target" "$backup" || {
            rm -f "$replacement"
            return 1
        }
        echo "已备份当前配置: $backup"
    fi

    mv -f "$replacement" "$target" || return 1
    if declare -F set_hysteria_file_permissions >/dev/null; then
        set_hysteria_file_permissions "$target"
    else
        chmod 600 "$target"
    fi
}

config_advanced_edit_full_yaml() {
    local target candidate editor
    target="$(config_advanced_target)"
    editor="${EDITOR:-nano}"
    candidate="$(mktemp "$(dirname "$target")/.config.yaml.edit.XXXXXX")" || return 1
    chmod 600 "$candidate"
    [[ -f "$target" ]] && cp -a "$target" "$candidate"

    "$editor" "$candidate" || {
        rm -f "$candidate"
        return 1
    }

    if config_advanced_apply "$candidate"; then
        rm -f "$candidate"
        echo "高级配置已保存并通过内核校验。"
        return 0
    fi

    echo "候选配置未通过校验，未修改当前配置: $candidate"
    return 1
}

config_advanced_set_scalar() {
    local key="$1" value="$2" target temp
    target="$(config_advanced_target)"
    [[ -f "$target" ]] || return 1
    temp="$(mktemp "$(dirname "$target")/.config.yaml.field.XXXXXX")" || return 1

    awk -v key="$key" -v value="$value" '
        BEGIN { changed = 0 }
        $0 ~ "^[[:space:]]*" key ":[[:space:]]*" {
            print key ": " value
            changed = 1
            next
        }
        { print }
        END { if (!changed) print key ": " value }
    ' "$target" > "$temp" || {
        rm -f "$temp"
        return 1
    }
    config_advanced_apply "$temp"
    local result=$?
    rm -f "$temp"
    return "$result"
}

config_advanced_edit_scalar() {
    local key="$1" label="$2" current value
    current="$(sed -n "s/^[[:space:]]*$key:[[:space:]]*//p" "$(config_advanced_target)" | head -1)"
    echo "当前 $label: ${current:-未设置}"
    echo -n "请输入新的 $label: "
    read -r value
    [[ -n "$value" ]] || return 0
    config_advanced_set_scalar "$key" "$value"
}

config_advanced_menu() {
    local choice
    while true; do
        clear
        echo "=== 高级配置 ==="
        echo "1. 编辑完整 YAML（保留所有官方字段）"
        echo "2. 修改监听地址和端口"
        echo "3. 修改忽略客户端带宽"
        echo "4. 修改 UDP 空闲超时"
        echo "5. 修改禁用 UDP"
        echo "6. 修改 ACL 文件路径"
        echo "7. 编辑带宽、TLS/ACME、认证、混淆、伪装、出站和路由"
        echo "0. 返回"
        echo -n "请选择 [0-7]: "
        read -r choice
        case "$choice" in
            1) config_advanced_edit_full_yaml ;;
            2) config_advanced_edit_scalar listen "监听地址和端口" ;;
            3) config_advanced_edit_scalar ignoreClientBandwidth "忽略客户端带宽" ;;
            4) config_advanced_edit_scalar udpIdleTimeout "UDP 空闲超时" ;;
            5) config_advanced_edit_scalar disableUDP "禁用 UDP" ;;
            6) config_advanced_edit_scalar acl "ACL 文件路径" ;;
            7) config_advanced_edit_full_yaml ;;
            0) return 0 ;;
            *) echo "无效选项" ;;
        esac
        read -r -p "按回车键继续..."
    done
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    config_advanced_menu
fi
