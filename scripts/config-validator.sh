#!/usr/bin/env bash

config_validate_with_core() {
    local candidate="$1" binary="${HYSTERIA_BIN:-hysteria}" timeout_seconds="${CONFIG_VALIDATE_TIMEOUT:-3}"
    local probe output status

    [[ -f "$candidate" ]] || return 1
    command -v timeout >/dev/null 2>&1 || {
        echo "缺少 timeout，无法进行内核配置校验。" >&2
        return 1
    }

    probe="$(mktemp "$(dirname "$candidate")/.config.yaml.validate.XXXXXX")" || return 1
    awk '
        BEGIN { replaced = 0 }
        /^[[:space:]]*listen:[[:space:]]*/ && $0 !~ /^[[:space:]]/ {
            print "listen: 127.0.0.1:0"
            replaced = 1
            next
        }
        /^[[:space:]]+listenHTTP:[[:space:]]*/ || /^[[:space:]]+listenHTTPS:[[:space:]]*/ { next }
        { print }
        END { if (!replaced) print "listen: 127.0.0.1:0" }
    ' "$candidate" > "$probe" || {
        rm -f "$probe"
        return 1
    }

    output="$(timeout --signal=TERM "$timeout_seconds" "$binary" server --config "$probe" --disable-update-check --log-level error 2>&1)"
    status=$?
    rm -f "$probe"

    if [[ "$output" == *"server up and running"* ]]; then
        return 0
    fi

    [[ -n "$output" ]] && printf '%s\n' "$output" >&2
    [[ "$status" -eq 124 ]] && echo "内核在完成配置校验前超时。" >&2
    return 1
}
