#!/usr/bin/env bash

set -uo pipefail

HY_UPDATE_RELEASE_API="${HY_UPDATE_RELEASE_API:-https://api.github.com/repos/apernet/hysteria/releases/latest}"
HY_UPDATE_INSTALL_URL="${HY_UPDATE_INSTALL_URL:-https://get.hy2.sh/}"

hy_update_normalize_version() {
    local version="$1"
    version="${version#app/}"
    version="${version#v}"
    echo "$version" | grep -oE '[0-9]+(\.[0-9]+){1,3}' | head -1
}

hy_update_extract_latest_tag() {
    local json="$1"
    echo "$json" | sed -n 's/.*"tag_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1
}

hy_update_current_version() {
    local output=""

    if command -v hysteria >/dev/null 2>&1; then
        output="$(hysteria version 2>/dev/null | head -1 || true)"
        [[ -n "$output" ]] || output="$(hysteria --version 2>/dev/null | head -1 || true)"
        [[ -n "$output" ]] || output="$(hysteria -v 2>/dev/null | head -1 || true)"
    fi

    hy_update_normalize_version "$output"
}

hy_update_latest_version() {
    local json
    json="$(curl -fsSL --connect-timeout 8 --max-time 20 "$HY_UPDATE_RELEASE_API")" || return 1
    hy_update_normalize_version "$(hy_update_extract_latest_tag "$json")"
}

hy_update_is_newer() {
    local latest
    local current
    latest="$(hy_update_normalize_version "$1")"
    current="$(hy_update_normalize_version "$2")"

    [[ -n "$latest" ]] || return 1
    [[ -n "$current" ]] || return 0
    [[ "$latest" == "$current" ]] && return 1

    [[ "$(printf '%s\n%s\n' "$current" "$latest" | sort -V | tail -1)" == "$latest" ]]
}

hy_update_install_or_upgrade() {
    bash <(curl -fsSL "$HY_UPDATE_INSTALL_URL")
}

manage_hysteria_update() {
    echo ""
    echo "=== Hysteria2 内核更新 ==="

    local current latest
    current="$(hy_update_current_version)"
    latest="$(hy_update_latest_version 2>/dev/null || true)"

    echo "当前版本: ${current:-未安装或无法检测}"
    echo "最新版本: ${latest:-无法获取}"
    echo ""

    if [[ -n "$latest" ]] && hy_update_is_newer "$latest" "$current"; then
        echo "检测到新版本。"
    elif [[ -n "$current" && -n "$latest" ]]; then
        echo "当前已是最新版本。"
    fi

    echo -n "是否通过官方脚本安装/更新 Hysteria2? [y/N]: "
    local choice
    read -r choice
    if [[ "$choice" =~ ^[Yy]$ ]]; then
        hy_update_install_or_upgrade
    fi
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    case "${1:-}" in
        --current)
            hy_update_current_version
            ;;
        --latest)
            hy_update_latest_version
            ;;
        --install|--upgrade)
            hy_update_install_or_upgrade
            ;;
        *)
            manage_hysteria_update
            ;;
    esac
fi
