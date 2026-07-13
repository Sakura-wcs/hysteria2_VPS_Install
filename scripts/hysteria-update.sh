#!/usr/bin/env bash

set -uo pipefail

HY_UPDATE_RELEASE_API="${HY_UPDATE_RELEASE_API:-https://api.github.com/repos/apernet/hysteria/releases/latest}"
HY_UPDATE_TAGS_API="${HY_UPDATE_TAGS_API:-https://api.github.com/repos/apernet/hysteria/tags?per_page=20}"
HY_UPDATE_LATEST_URL="${HY_UPDATE_LATEST_URL:-https://github.com/apernet/hysteria/releases/latest}"
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

hy_update_extract_first_semver_tag() {
    local json="$1"
    local tag
    while IFS= read -r tag; do
        if [[ -n "$(hy_update_normalize_version "$tag")" ]]; then
            echo "$tag"
            return 0
        fi
    done < <(
        echo "$json" |
            grep -oE '"name"[[:space:]]*:[[:space:]]*"[^"]+"' |
            sed -n 's/.*"name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p'
    )
}

hy_update_extract_redirect_tag() {
    local headers="$1"
    echo "$headers" |
        tr -d '\r' |
        sed -n 's/^[Ll]ocation:[[:space:]]*.*\/tag\/\([^/?#[:space:]]*\).*/\1/p' |
        tail -1
}

hy_update_curl_json() {
    local url="$1"
    curl -fsSL \
        --connect-timeout 8 \
        --max-time 20 \
        -H "Accept: application/vnd.github+json" \
        -H "User-Agent: s-hy2-manager" \
        "$url"
}

hy_update_find_binary() {
    local candidate

    candidate="$(command -v hysteria 2>/dev/null || true)"
    if [[ -n "$candidate" && -x "$candidate" ]]; then
        echo "$candidate"
        return 0
    fi

    for candidate in /usr/local/bin/hysteria /usr/bin/hysteria /opt/hysteria/hysteria; do
        if [[ -x "$candidate" ]]; then
            echo "$candidate"
            return 0
        fi
    done

    return 1
}

hy_update_binary_version() {
    local binary="$1"
    local output version

    for arg in version --version -v; do
        output="$("$binary" "$arg" 2>&1 || true)"
        version="$(hy_update_normalize_version "$output")"
        if [[ -n "$version" ]]; then
            echo "$version"
            return 0
        fi
    done

    return 1
}

hy_update_current_version() {
    local binary

    binary="$(hy_update_find_binary 2>/dev/null || true)"
    [[ -n "$binary" ]] || return 0

    hy_update_binary_version "$binary" || true
}

hy_update_latest_version() {
    local json headers version

    if json="$(hy_update_curl_json "$HY_UPDATE_RELEASE_API" 2>/dev/null)"; then
        version="$(hy_update_normalize_version "$(hy_update_extract_latest_tag "$json")")"
        if [[ -n "$version" ]]; then
            echo "$version"
            return 0
        fi
    fi

    if json="$(hy_update_curl_json "$HY_UPDATE_TAGS_API" 2>/dev/null)"; then
        version="$(hy_update_normalize_version "$(hy_update_extract_first_semver_tag "$json")")"
        if [[ -n "$version" ]]; then
            echo "$version"
            return 0
        fi
    fi

    headers="$(curl -fsSLI --connect-timeout 8 --max-time 20 "$HY_UPDATE_LATEST_URL" 2>/dev/null || true)"
    version="$(hy_update_normalize_version "$(hy_update_extract_redirect_tag "$headers")")"
    if [[ -n "$version" ]]; then
        echo "$version"
        return 0
    fi

    return 1
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

hy_update_decision() {
    local latest current
    latest="$(hy_update_normalize_version "$1")"
    current="$(hy_update_normalize_version "$2")"

    [[ -n "$latest" ]] || {
        echo "unavailable-latest"
        return 0
    }

    [[ -n "$current" ]] || {
        echo "unknown-current"
        return 0
    }

    [[ "$latest" == "$current" ]] && {
        echo "current"
        return 0
    }

    if hy_update_is_newer "$latest" "$current"; then
        echo "upgrade"
    else
        echo "installed-newer"
    fi
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

    local decision choice
    decision="$(hy_update_decision "$latest" "$current")"

    case "$decision" in
        current)
            echo "当前已是最新版本，无需更新。"
            echo -n "是否强制通过官方脚本重新安装 Hysteria2? [y/N]: "
            read -r choice
            [[ "$choice" =~ ^[Yy]$ ]] && hy_update_install_or_upgrade
            return 0
            ;;
        upgrade)
            echo "检测到新版本。"
            echo -n "是否通过官方脚本更新 Hysteria2? [y/N]: "
            read -r choice
            [[ "$choice" =~ ^[Yy]$ ]] && hy_update_install_or_upgrade
            return 0
            ;;
        installed-newer)
            echo "当前安装版本高于检测到的最新稳定版本，未执行更新。"
            return 0
            ;;
        unknown-current)
            echo "无法检测当前版本，可选择通过官方脚本安装或修复。"
            echo -n "是否通过官方脚本安装 Hysteria2? [y/N]: "
            read -r choice
            [[ "$choice" =~ ^[Yy]$ ]] && hy_update_install_or_upgrade
            return 0
            ;;
        *)
            echo "无法获取最新版本，未执行更新。"
            return 1
            ;;
    esac
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
