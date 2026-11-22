#!/usr/bin/env bash

config_write_probe() {
    "${CONFIG_VALIDATE_PYTHON:-python3}" - "$1" "$2" <<'PY'
import re
import sys

try:
    import yaml
except ImportError:
    print('配置探测需要 Python 3 和 PyYAML。', file=sys.stderr)
    sys.exit(2)


class ProbeLoader(yaml.SafeLoader):
    pass


# Preserve YAML 1.2-style strings such as unquoted on/off and dates.
ProbeLoader.yaml_implicit_resolvers = {
    key: [(tag, pattern) for tag, pattern in entries
          if tag not in ('tag:yaml.org,2002:bool', 'tag:yaml.org,2002:timestamp')]
    for key, entries in yaml.SafeLoader.yaml_implicit_resolvers.items()
}
ProbeLoader.add_implicit_resolver('tag:yaml.org,2002:bool',
                                  re.compile(r'^(?:true|True|TRUE|false|False|FALSE)$'),
                                  list('tTfF'))

try:
    with open(sys.argv[1], encoding='utf-8-sig') as source:
        config = yaml.load(source, Loader=ProbeLoader)
    if not isinstance(config, dict):
        raise ValueError
    for key in list(config):
        if isinstance(key, str):
            if key.lower() in ('listen', 'trafficstats', 'mimic'):
                del config[key]
            elif key.lower() == 'masquerade' and isinstance(config[key], dict):
                config[key] = {k: v for k, v in config[key].items()
                               if not isinstance(k, str) or k.lower() not in ('listenhttp', 'listenhttps')}
    config['listen'] = '127.0.0.1:0'
    with open(sys.argv[2], 'w', encoding='utf-8') as target:
        yaml.safe_dump(config, target, allow_unicode=True)
except (OSError, ValueError, yaml.YAMLError, RecursionError):
    print('无法解析或暂存候选 YAML 配置。', file=sys.stderr)
    sys.exit(1)
PY
}

config_validate_with_core() (
    local candidate="$1" binary="${HYSTERIA_BIN:-hysteria}" timeout_seconds="${CONFIG_VALIDATE_TIMEOUT:-3}"
    local probe output status

    [[ -f "$candidate" ]] || return 1
    command -v timeout >/dev/null 2>&1 || {
        echo "缺少 timeout，无法进行内核配置校验。" >&2
        return 2
    }
    command -v "${CONFIG_VALIDATE_PYTHON:-python3}" >/dev/null 2>&1 || {
        echo '配置探测需要 Python 3 和 PyYAML。' >&2
        return 2
    }

    probe="$(mktemp --suffix=.yaml "$(dirname "$candidate")/.config.validate.XXXXXX")" || return 1
    trap 'rm -f -- "$probe"' EXIT
    trap 'exit 130' INT
    trap 'exit 143' TERM
    config_write_probe "$candidate" "$probe" || return $?

    status=0
    output="$(timeout --signal=TERM --kill-after=1 "$timeout_seconds" "$binary" server --config "$probe" --disable-update-check --log-level info --log-format json 2>&1)" || status=$?

    if [[ "$status" -eq 124 ]] && grep -qF '"msg":"server up and running"' <<< "$output"; then
        return 0
    fi

    [[ -n "$output" ]] && printf '%s\n' "$output" >&2
    [[ "$status" -eq 124 ]] && echo "内核在完成配置校验前超时。" >&2
    return 1
)
