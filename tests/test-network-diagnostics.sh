#!/usr/bin/env bash

set -u

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/tests/test-helper.sh"
case "$OSTYPE" in msys*|cygwin*) export CONFIG_VALIDATE_PYTHON="${CONFIG_VALIDATE_PYTHON:-python}" ;; esac

TEST_TMP="$(mktemp -d)"
trap 'rm -rf "$TEST_TMP"' EXIT

SYSCTL_CONF="$TEST_TMP/99-s-hy2-network.conf"
SYSCTL_LOG="$TEST_TMP/sysctl.log"
SYSCTL_BIN="$TEST_TMP/sysctl"
cat > "$SYSCTL_BIN" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$SYSCTL_LOG"
EOF
chmod +x "$SYSCTL_BIN"
export SYSCTL_CONF SYSCTL_LOG SYSCTL_BIN

source "$ROOT/scripts/network-tuning.sh"

network_write_bbr_fq
assert_file_contains "$SYSCTL_CONF" 'net.core.default_qdisc=fq'
assert_file_contains "$SYSCTL_CONF" 'net.ipv4.tcp_congestion_control=bbr'
assert_contains "$(<"$SYSCTL_LOG")" "-p $SYSCTL_CONF"

DIAGNOSTIC_CONFIG="$TEST_TMP/config.yaml"
HYSTERIA_BIN="$TEST_TMP/hysteria"
printf '%s\n' 'listen: :443' 'auth:' '  type: password' '  password: test' > "$DIAGNOSTIC_CONFIG"
cat > "$HYSTERIA_BIN" <<'EOF'
#!/usr/bin/env bash
if [[ "$1" == server && "$2" == --config && "$3" == *.yaml && -f "$3" && "$5 $6 $7 $8" == '--log-level info --log-format json' ]]; then
    echo '{"level":"info","msg":"server up and running"}' >&2
    sleep 2
    exit 0
fi
exit 2
EOF
chmod +x "$HYSTERIA_BIN"
CONFIG_VALIDATE_TIMEOUT=1
export DIAGNOSTIC_CONFIG HYSTERIA_BIN CONFIG_VALIDATE_TIMEOUT

DIAGNOSTIC_RESULTS=""
DIAGNOSTIC_REPAIRABLE=""
source "$ROOT/scripts/config-validator.sh"
source "$ROOT/scripts/diagnostics.sh"
diagnostic_collect
assert_contains "$DIAGNOSTIC_RESULTS" 'config:ok'
assert_contains "$DIAGNOSTIC_REPAIRABLE" 'network-bbr-fq'

DIAGNOSTIC_RESULTS=''
CONFIG_VALIDATE_PYTHON="$TEST_TMP/missing-python" diagnostic_check_config || true
assert_contains "$DIAGNOSTIC_RESULTS" 'config:warning:'
assert_contains "$DIAGNOSTIC_RESULTS" 'PyYAML'

CONFIG_ADVANCED_PATH="$TEST_TMP/live-config.yaml"
candidate="$TEST_TMP/candidate.yaml"
printf '%s\n' 'listen: :443' 'auth:' '  type: password' '  password: test' > "$candidate"
source "$ROOT/scripts/config-advanced.sh"
config_advanced_apply "$candidate"
assert_file_contains "$CONFIG_ADVANCED_PATH" 'listen: :443'
(
    unset EDITOR VISUAL
    command() {
        [[ "${1:-}" != -v || "${2:-}" != nano ]] || return 1
        builtin command "$@"
    }
    nano() { return 1; }
    vi() { printf '\n# edited with vi\n' >> "$1"; }
    config_advanced_edit_full_yaml >/dev/null
) || fail 'validated editor did not fall back to vi when nano was unavailable'
assert_file_contains "$CONFIG_ADVANCED_PATH" '# edited with vi'
menu_text="$(config_advanced_menu_text)"
assert_contains "$menu_text" '编辑完整 YAML'
assert_not_contains "$menu_text" '修改 ACL 文件路径'
assert_not_contains "$menu_text" '编辑带宽、TLS/ACME、认证、混淆、伪装、出站和路由'

diagnostic_collect() {
    DIAGNOSTIC_RESULTS=""
    DIAGNOSTIC_REPAIRABLE=$'file-permissions\n'
}

diagnostic_repair() {
    printf 'repaired:%s\n' "$1"
}

if diagnostic_output="$(printf '1\ny\n' | diagnostic_show 2>&1)"; then
    diagnostic_status=0
else
    diagnostic_status=$?
fi
assert_equals 0 "$diagnostic_status"
assert_contains "$diagnostic_output" 'repaired:file-permissions'

finish_tests
