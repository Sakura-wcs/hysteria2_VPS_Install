#!/usr/bin/env bash

set -uo pipefail

CERT_SYNC_DEST_ROOT="${CERT_SYNC_DEST_ROOT:-/etc/hysteria2/certs}"
CERT_SYNC_CONFIG_PATH="${CERT_SYNC_CONFIG_PATH:-/etc/hysteria/config.yaml}"
CERT_SYNC_CRON_SCHEDULE="${CERT_SYNC_CRON_SCHEDULE:-0 4 * * *}"
CERT_SYNC_MARKER="s-hy2-cert-sync"

cert_sync_log() {
    echo "$*"
}

cert_sync_validate_domain() {
    local domain="$1"
    [[ "$domain" =~ ^[A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?(\.[A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?)+$ ]]
}

cert_sync_search_roots() {
    if [[ -n "${CERT_SYNC_SEARCH_ROOTS:-}" ]]; then
        printf '%s\n' $CERT_SYNC_SEARCH_ROOTS
        return
    fi

    printf '%s\n' \
        "/etc/letsencrypt/live" \
        "/root/.acme.sh" \
        "${HOME:-/root}/.acme.sh"
}

cert_sync_candidate_dirs() {
    local domain="$1"
    local root

    while IFS= read -r root; do
        [[ -n "$root" ]] || continue
        printf '%s\n' \
            "$root/$domain" \
            "$root/${domain}_ecc"
    done < <(cert_sync_search_roots)
}

cert_sync_find_pair_in_dir() {
    local domain="$1"
    local dir="$2"
    local cert=""
    local key=""

    [[ -d "$dir" ]] || return 1

    local cert_candidates=(
        "$dir/fullchain.pem"
        "$dir/fullchain.cer"
        "$dir/${domain}.cer"
        "$dir/${domain}.crt"
        "$dir/cert.pem"
    )
    local key_candidates=(
        "$dir/privkey.pem"
        "$dir/${domain}.key"
        "$dir/private.key"
    )

    local path
    for path in "${cert_candidates[@]}"; do
        if [[ -f "$path" ]]; then
            cert="$path"
            break
        fi
    done

    for path in "${key_candidates[@]}"; do
        if [[ -f "$path" ]]; then
            key="$path"
            break
        fi
    done

    [[ -n "$cert" && -n "$key" ]] || return 1
    printf '%s|%s\n' "$cert" "$key"
}

cert_sync_find_pair() {
    local domain="$1"
    local dir

    cert_sync_validate_domain "$domain" || return 2

    while IFS= read -r dir; do
        cert_sync_find_pair_in_dir "$domain" "$dir" && return 0
    done < <(cert_sync_candidate_dirs "$domain")

    return 1
}

cert_sync_copy_domain_cert() {
    local domain="$1"
    local pair="$2"
    local cert_source="${pair%%|*}"
    local key_source="${pair#*|}"
    local dest_dir="$CERT_SYNC_DEST_ROOT/$domain"
    local dest_cert="$dest_dir/fullchain.pem"
    local dest_key="$dest_dir/privkey.pem"

    mkdir -p "$dest_dir" || return 1
    cp "$cert_source" "$dest_cert" || return 1
    cp "$key_source" "$dest_key" || return 1
    chmod 644 "$dest_cert" 2>/dev/null || true
    chmod 600 "$dest_key" 2>/dev/null || true
    chown hysteria:hysteria "$dest_cert" "$dest_key" 2>/dev/null || true

    printf '%s|%s\n' "$dest_cert" "$dest_key"
}

cert_sync_update_tls_config() {
    local cert_file="$1"
    local key_file="$2"
    local config_file="${3:-$CERT_SYNC_CONFIG_PATH}"

    [[ -f "$config_file" ]] || return 1
    cp "$config_file" "$config_file.bak.$(date +%Y%m%d%H%M%S)" || return 1

    sed -i '/^acme:/,/^[[:alpha:]][[:alnum:]_-]*:/ {
        /^acme:/d
        /^[[:alpha:]][[:alnum:]_-]*:/!d
    }' "$config_file"

    if grep -q '^tls:' "$config_file"; then
        sed -i "/^tls:/,/^[[:alpha:]][[:alnum:]_-]*:/ {
            s|^[[:space:]]*cert:.*|  cert: $cert_file|
            s|^[[:space:]]*key:.*|  key: $key_file|
        }" "$config_file"

        if ! grep -A 8 '^tls:' "$config_file" | grep -q 'cert:'; then
            sed -i "/^tls:/a\\  cert: $cert_file" "$config_file"
        fi
        if ! grep -A 8 '^tls:' "$config_file" | grep -q 'key:'; then
            sed -i "/^tls:/a\\  key: $key_file" "$config_file"
        fi
    else
        {
            echo ""
            echo "tls:"
            echo "  cert: $cert_file"
            echo "  key: $key_file"
        } >> "$config_file"
    fi
}

cert_sync_script_path() {
    if [[ -n "${CERT_SYNC_SCRIPT_PATH:-}" ]]; then
        echo "$CERT_SYNC_SCRIPT_PATH"
    else
        cd "$(dirname "${BASH_SOURCE[0]}")" && pwd
    fi
}

cert_sync_render_cron_line() {
    local domain="$1"
    local script_path="${2:-$(cert_sync_script_path)/certificate-sync.sh}"
    printf '%s %s --sync-domain %s # %s:%s\n' "$CERT_SYNC_CRON_SCHEDULE" "$script_path" "$domain" "$CERT_SYNC_MARKER" "$domain"
}

cert_sync_install_cron() {
    local domain="$1"
    local cron_line
    cron_line="$(cert_sync_render_cron_line "$domain")"

    if [[ -n "${CERT_SYNC_CRON_FILE:-}" ]]; then
        grep -v "# $CERT_SYNC_MARKER:$domain" "$CERT_SYNC_CRON_FILE" 2>/dev/null > "$CERT_SYNC_CRON_FILE.tmp" || true
        printf '%s\n' "$cron_line" >> "$CERT_SYNC_CRON_FILE.tmp"
        mv "$CERT_SYNC_CRON_FILE.tmp" "$CERT_SYNC_CRON_FILE"
        return 0
    fi

    local current
    current="$(crontab -l 2>/dev/null | grep -v "# $CERT_SYNC_MARKER:$domain" || true)"
    { printf '%s\n' "$current"; printf '%s\n' "$cron_line"; } | crontab -
}

cert_sync_remove_cron() {
    local domain="$1"

    if [[ -n "${CERT_SYNC_CRON_FILE:-}" ]]; then
        grep -v "# $CERT_SYNC_MARKER:$domain" "$CERT_SYNC_CRON_FILE" 2>/dev/null > "$CERT_SYNC_CRON_FILE.tmp" || true
        mv "$CERT_SYNC_CRON_FILE.tmp" "$CERT_SYNC_CRON_FILE"
        return 0
    fi

    crontab -l 2>/dev/null | grep -v "# $CERT_SYNC_MARKER:$domain" | crontab -
}

cert_sync_domain_once() {
    local domain="$1"
    local pair
    local dest_pair

    pair="$(cert_sync_find_pair "$domain")" || {
        cert_sync_log "未找到域名证书: $domain"
        return 1
    }
    dest_pair="$(cert_sync_copy_domain_cert "$domain" "$pair")" || return 1
    cert_sync_update_tls_config "${dest_pair%%|*}" "${dest_pair#*|}" || return 1
    cert_sync_log "证书已同步到: ${dest_pair%%|*}"
}

manage_certificate_sync() {
    local domain
    echo ""
    echo "=== 域名证书同步 ==="
    echo -n "请输入域名: "
    read -r domain

    if ! cert_sync_validate_domain "$domain"; then
        cert_sync_log "域名格式无效"
        return 1
    fi

    if cert_sync_domain_once "$domain"; then
        echo -n "是否创建每天 04:00 自动同步任务? [Y/n]: "
        local enable_cron
        read -r enable_cron
        if [[ ! "$enable_cron" =~ ^[Nn]$ ]]; then
            cert_sync_install_cron "$domain"
            cert_sync_log "已创建定时同步任务"
        fi
    fi
}

cert_sync_main() {
    case "${1:-}" in
        --sync-domain)
            shift
            cert_sync_domain_once "${1:-}"
            ;;
        --install-cron)
            shift
            cert_sync_install_cron "${1:-}"
            ;;
        --remove-cron)
            shift
            cert_sync_remove_cron "${1:-}"
            ;;
        *)
            echo "Usage: $0 --sync-domain <domain> | --install-cron <domain> | --remove-cron <domain>"
            return 2
            ;;
    esac
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    cert_sync_main "$@"
fi
